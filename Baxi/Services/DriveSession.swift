import Foundation
import CoreLocation
import Observation

/// One drive in progress. Feeds location fixes (real GPS or a replay) to RouteFollower, asks
/// CueScheduler which cue fires, fills in the light count, speaks it, and publishes what the
/// Drive screen shows. The screen itself has no logic.
@Observable
final class DriveSession {
    enum Mode: Equatable { case live, replay(speedMultiplier: Double) }

    private(set) var route: PlannedRoute { didSet { routeCoordinates = route.polyline.points.map(\.clLocation) } }
    /// The route line for the map, converted once per route rather than on every location fix.
    private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    let level: ExperienceLevel
    let mode: Mode
    private(set) var cues: [Cue]
    private var signals: [Double]
    private var speeds: [(along: Double, mph: Int)]
    private var follower: RouteFollower
    private var scheduler = CueScheduler()
    private let speaker: SpeechOutput
    private let cache: OSMCache
    private let features: [RoadFeature]
    private let highInjury: HighInjuryNetwork?
    /// Where the drive began, for the sunset split.
    let startCoordinate: Coordinate?

    // What the Drive screen shows.
    private(set) var progress: RouteProgress?
    private(set) var position: Coordinate?
    private(set) var heading: Double = 0
    private(set) var lastCue: Cue?
    private(set) var lastCueText: String = ""
    private(set) var laneStrip: LaneStrip?
    private(set) var spokenLog: [(meters: Double, text: String)] = []
    private(set) var isFinished = false
    private(set) var startedAt = Date()
    private(set) var endedAt: Date?
    static let locationOffText = "Location is off. Turn it on in Settings."
    private(set) var isRerouting = false
    private(set) var rerouteCount = 0
    /// Meters driven on routes replaced by a reroute.
    private var metersBeforeReroute = 0.0
    /// Where on the first route the drive actually began (a replay can skip ahead, a live drive can
    /// start partway along), so the distance driven does not count the part before it.
    private var firstAlongMeters: Double?
    /// Maneuvers the car has gone through on this drive, for the Arrived screen.
    private(set) var passedManeuvers: [Maneuver] = []
    private var passedAlong = 0.0
    /// More progress than this in one location fix is a jump along the route, not driving.
    static let maxJumpMeters = 250.0
    private var lastRerouteAttempt: TimeInterval = -.infinity
    /// False until the car is first within 30 m of the route; a live drive started from somewhere
    /// else (a preset loop started from home) is guided to the route's start right away.
    private var hasReachedRoute = false

    private var replayTimer: Timer?
    private var replayMeters = 0.0
    private var clock: TimeInterval = 0
    private var locationDelegate: LocationDelegate?

    var muted = false {
        didSet { speaker.isMuted = muted }
    }

    init(route: PlannedRoute, cache: OSMCache, features: [RoadFeature], highInjury: HighInjuryNetwork?,
         level: ExperienceLevel, mode: Mode, speaker: SpeechOutput = Speaker()) {
        self.speaker = speaker
        self.route = route
        self.routeCoordinates = route.polyline.points.map(\.clLocation)
        self.level = level
        self.mode = mode
        self.cache = cache
        self.features = features
        self.highInjury = highInjury
        startCoordinate = route.polyline.points.first
        (cues, signals, speeds) = Self.prepare(route, cache: cache, features: features, highInjury: highInjury, level: level)
        follower = RouteFollower(polyline: route.polyline)
        position = route.polyline.points.first
    }

    private static func prepare(_ route: PlannedRoute, cache: OSMCache, features: [RoadFeature], highInjury: HighInjuryNetwork?,
                                level: ExperienceLevel) -> ([Cue], [Double], [(along: Double, mph: Int)]) {
        let built = CueListBuilder.build(route: route, cache: cache, features: features, highInjury: highInjury)
        let targets = route.maneuvers.filter(\.needsLaneChoice).map(\.alongMeters).sorted()
        return (CueScheduler.plan(built, level: level, maneuverTargets: targets),
                CueListBuilder.signalAlongs(line: route.polyline, cache: cache),
                CueListBuilder.speedProfile(line: route.polyline, cache: cache))
    }

    /// Total meters driven this drive, across reroutes.
    var drivenMeters: Double {
        max(0, metersBeforeReroute + (progress?.alongMeters ?? 0) - (firstAlongMeters ?? 0) + arrivalCreditMeters)
    }
    /// The gap between where the drive ended (within `arrivalMeters`) and the destination.
    private var arrivalCreditMeters = 0.0

    /// The posted limit where the car is, from OpenStreetMap maxspeed tags. nil where untagged.
    var speedLimitMph: Int? {
        let along = progress?.alongMeters ?? 0
        return CueListBuilder.speed(at: along, in: speeds)
    }

    /// A school zone or crash-heavy corridor the car is in or about to enter, shown as a chip.
    var activeAlert: Cue? {
        let along = progress?.alongMeters ?? 0
        return cues.first { ($0.kind == .schoolZone || $0.kind == .crashCorridor) && along >= $0.targetMeters - 150 && along <= $0.targetMeters + 500 }
    }

    // MARK: The next maneuver, for the big card

    var nextManeuver: Maneuver? {
        let along = progress?.alongMeters ?? 0
        return route.maneuvers.first { $0.alongMeters > along + 5 && $0.kind != .depart && $0.kind != .continueStraight }
    }

    var metersToNextManeuver: Double? {
        nextManeuver.map { max(0, $0.alongMeters - (progress?.alongMeters ?? 0)) }
    }

    var lightsToNextManeuver: Int? {
        guard let m = nextManeuver, m.needsLaneChoice else { return nil }
        let n = CueListBuilder.lightsBefore(maneuverAt: m.alongMeters, from: progress?.alongMeters ?? 0, signals: signals)
        return n > 0 ? n : nil
    }

    // MARK: Start and stop

    func start() {
        startedAt = Date()
        speaker.say("Starting \(route.name). The driver keeps hands on the wheel, I will call everything out.")
        switch mode {
        case .replay(let mult): startReplay(multiplier: mult)
        case .live: startLive()
        }
    }

    /// `stopSpeech` is false on arrival, so "You have arrived" is heard to the end.
    func end(stopSpeech: Bool = true) {
        guard !isFinished else { return }
        replayTimer?.invalidate(); replayTimer = nil
        locationDelegate?.manager.stopUpdatingLocation(); locationDelegate = nil
        if stopSpeech { speaker.stop() }
        endedAt = Date()
        isFinished = true
    }

    /// Replays the route at a believable speed: the posted limit where known, else 30 mph,
    /// slowed to 15 mph near roundabouts and turns. `multiplier` speeds the clock for testing.
    private func startReplay(multiplier: Double) {
        let tick = 0.25
        replayTimer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            guard let self else { return }
            let mps = self.replaySpeed(at: self.replayMeters)
            self.replayMeters = min(self.route.polyline.lengthMeters, self.replayMeters + mps * tick * multiplier)
            self.clock += tick * multiplier
            if let c = self.route.polyline.coordinate(atMeters: self.replayMeters) { self.feed(c, at: self.clock) }
            if self.replayMeters >= self.route.polyline.lengthMeters { self.replayTimer?.invalidate() }
        }
    }

    /// Replay only: start partway along the route. Cues before that point are marked as passed.
    func skip(toMeters meters: Double) {
        guard case .replay = mode else { return }
        replayMeters = max(0, min(meters, route.polyline.lengthMeters))
        clock = 0
        if let c = route.polyline.coordinate(atMeters: replayMeters) { feedSilently(c) }
    }

    private func feedSilently(_ c: Coordinate) {
        progress = follower.update(location: c, at: clock)
        firstAlongMeters = progress?.alongMeters
        passedAlong = progress?.alongMeters ?? 0
        heading = route.polyline.bearing(atMeters: replayMeters) ?? heading
        for cue in cues where cue.targetMeters < replayMeters { scheduler.markFired(cue.id) }
        position = c
    }

    /// Drives the whole route at once, no timer: a fix every `step` meters at the replay speed.
    /// For tests and the transcript tool (`swift run baxi-transcript`). Returns what was spoken.
    @discardableResult
    func simulateWholeRoute(step: Double = 5) -> [(meters: Double, text: String)] {
        var meters = replayMeters, t = 0.0
        while !isFinished && meters < route.polyline.lengthMeters {
            meters = min(route.polyline.lengthMeters, meters + step)
            t += step / replaySpeed(at: meters)
            if let c = route.polyline.coordinate(atMeters: meters) { feed(c, at: t) }
        }
        if !isFinished { end() }
        return spokenLog
    }

    private func replaySpeed(at meters: Double) -> Double {
        let nearManeuver = route.maneuvers.contains { $0.needsLaneChoice && abs($0.alongMeters - meters) < 60 }
        if nearManeuver { return 6.7 }   // 15 mph
        let mph = cues.last { $0.targetMeters <= meters && $0.roadSpeedMph != nil }?.roadSpeedMph ?? 30
        return Double(mph) * 0.447 * 0.9
    }

    private func startLive() {
        let d = LocationDelegate(onFix: { [weak self] loc in
            guard let self else { return }
            self.clock = loc.timestamp.timeIntervalSince(self.startedAt)
            self.feed(Coordinate(loc.coordinate), at: self.clock)
        }, onDenied: { [weak self] in
            guard let self, self.lastCueText != Self.locationOffText else { return }
            self.lastCueText = Self.locationOffText
            self.speaker.say("Location is off for Baxi. Pull over, then turn it on in Settings.")
        })
        locationDelegate = d
        d.manager.requestWhenInUseAuthorization()
        d.manager.startUpdatingLocation()
    }

    // MARK: Each location fix

    func feed(_ location: Coordinate, at time: TimeInterval) {
        guard !isFinished, let p = follower.update(location: location, at: time) else { return }
        if p.crossTrackMeters < 30 { hasReachedRoute = true }
        if mode == .live, !hasReachedRoute, p.crossTrackMeters > RouteFollower.offRouteMeters {
            // Still heading to the route: no progress, no cues, until the car is on it.
            position = location
            lastCueText = "Getting you to the start"
            if !saidGetToStart { saidGetToStart = true; speaker.say("First, let's get you to the start of the route.") }
            if !isRerouting, time - lastRerouteAttempt > 30 { reroute(from: location, at: time) }
            return
        }
        if progress == nil {
            if firstAlongMeters == nil { firstAlongMeters = p.alongMeters }
            passedAlong = p.alongMeters
        }
        progress = p
        if p.alongMeters - passedAlong > Self.maxJumpMeters {
            // The car joined the route further along (another road, a shortcut): what it skipped was
            // neither driven nor handled.
            firstAlongMeters = (firstAlongMeters ?? 0) + (p.alongMeters - passedAlong)
        } else {
            passedManeuvers += route.maneuvers.filter { $0.alongMeters > passedAlong && $0.alongMeters <= p.alongMeters }
        }
        passedAlong = max(passedAlong, p.alongMeters)
        position = p.crossTrackMeters > RouteFollower.offRouteMeters ? location : p.snapped
        heading = route.polyline.bearing(atMeters: p.alongMeters) ?? heading

        if p.isOffRoute {
            if lastCueText != "Off the route" {
                lastCueText = "Off the route"
                speaker.say("You are off the route. Keep driving safely, I am finding a new way.")
            }
            if mode == .live, !isRerouting, time - lastRerouteAttempt > 30 { reroute(from: location, at: time) }
            return
        }

        // The timeout filters GPS noise before declaring a missed route. It does not make
        // instructions on the old line valid while the car is already away from that line.
        guard p.crossTrackMeters <= RouteFollower.offRouteMeters else { return }

        if lastCueText == "Off the route" { lastCueText = "" }

        // A lane strip stays up from its cue until the maneuver is passed.
        if let c = lastLaneCue, p.alongMeters > c.targetMeters + 10 {
            laneStrip = nil; lastLaneCue = nil
        }

        if let cue = scheduler.due(from: cues, alongMeters: p.alongMeters, now: time) {
            let lights = lightsFor(cue, along: p.alongMeters)
            let spoken = cue.spoken(lights: lights)
            lastCue = cue
            lastCueText = cue.card(lights: lights)
            if let s = cue.laneStrip { laneStrip = s; lastLaneCue = cue }
            spokenLog.append((p.alongMeters, spoken))
            speaker.say(spoken)
        }
        // Within 30 m of the end counts as there: GPS is often 10 to 20 m off, and people park short.
        if p.remainingMeters < Self.arrivalMeters, previousAlong > route.polyline.lengthMeters - 300, !isFinished {
            if let arrive = cues.first(where: { $0.kind == .arrive }) { scheduler.markFired(arrive.id); lastCue = arrive }
            // The car is there: credit the last few meters and any turn in them, as if it drove to the pin.
            let destination = route.polyline.lengthMeters
            passedManeuvers += route.maneuvers.filter { $0.alongMeters > passedAlong && $0.alongMeters <= destination && $0.kind != .arrive }
            arrivalCreditMeters = max(0, destination - p.alongMeters)
            passedAlong = destination
            lastCueText = "Arrived"
            spokenLog.append((p.alongMeters, "You have arrived"))
            speaker.say("You have arrived")
            end(stopSpeech: false)
        }
        previousAlong = p.alongMeters
    }

    static let arrivalMeters = 30.0
    private var lastLaneCue: Cue?
    private var previousAlong = 0.0
    private var saidGetToStart = false

    // MARK: Reroute (live drives only)

    /// Asks for a way from where the car is back onto the planned route (a little ahead of where it
    /// left, or its start if the drive has not reached it yet), then swaps in approach + rest of route.
    /// Retries at most every 30 s. Replays never go off the route, so they never get here.
    private func reroute(from location: Coordinate, at time: TimeInterval) {
        let original = route
        let rejoin = original.rejoinMeters(leftAt: progress?.alongMeters ?? 0)
        guard let target = original.polyline.coordinate(atMeters: rejoin) else { return }
        isRerouting = true
        lastRerouteAttempt = time
        Task { @MainActor [weak self] in
            let approach = try? await RouteService.route(from: location, to: target, name: original.name)
            guard let self, !self.isFinished else { return }
            self.isRerouting = false
            guard let approach else { return }
            let new = original.rejoined(by: approach, at: rejoin)
            self.install(new)
            // The next instruction comes from the cues at its usual distance, not all at once here.
            self.speaker.say("New route")
        }
    }

    /// Replace the route while retaining completed distance, not its untraveled starting offset.
    /// Internal so tests can exercise reroute transitions without a network request.
    func install(_ new: PlannedRoute) {
        guard !isFinished else { return }
        metersBeforeReroute = drivenMeters
        firstAlongMeters = nil
        passedAlong = 0
        previousAlong = 0
        route = new
        (cues, signals, speeds) = Self.prepare(new, cache: cache, features: features, highInjury: highInjury, level: level)
        follower = RouteFollower(polyline: new.polyline)
        scheduler = CueScheduler()
        progress = nil
        lastCue = nil
        laneStrip = nil; lastLaneCue = nil
        lastCueText = "New route"
        rerouteCount += 1
    }

    private func lightsFor(_ cue: Cue, along: Double) -> Int? {
        guard let mid = cue.maneuverId, let m = route.maneuvers.first(where: { $0.id == mid }), m.needsLaneChoice else { return nil }
        switch cue.kind {
        case .laneChange, .signal:
            let n = CueListBuilder.lightsBefore(maneuverAt: m.alongMeters, from: along, signals: signals)
            return cue.kind == .signal ? n : (n > 0 ? n : nil)
        default: return nil
        }
    }

    var minutes: Double { ((endedAt ?? Date()).timeIntervalSince(startedAt)) / 60 }
}

private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    let onFix: (CLLocation) -> Void
    let onDenied: () -> Void

    init(onFix: @escaping (CLLocation) -> Void, onDenied: @escaping () -> Void) {
        self.onFix = onFix
        self.onDenied = onDenied
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        // Waiting at a long light must not pause updates; iOS is slow to resume them.
        manager.pausesLocationUpdatesAutomatically = false
        #if os(iOS)
        // Keeps cues going if the screen locks anyway (UIBackgroundModes location + audio in project.yml).
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        #endif
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted: onDenied()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // iOS often hands over a cached fix from minutes ago first; it would place the car where it was.
        for l in locations where l.horizontalAccuracy >= 0 && l.horizontalAccuracy < 50
            && abs(l.timestamp.timeIntervalSinceNow) < 10 { onFix(l) }
    }
}
