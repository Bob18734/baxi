import Foundation
import CoreLocation
import Observation

/// One drive in progress. Feeds location fixes (real GPS or a replay) to RouteFollower, asks
/// CueScheduler which cue fires, fills in the light count, speaks it, and publishes what the
/// Drive screen shows. The screen itself has no logic.
@Observable
final class DriveSession {
    enum Mode: Equatable { case live, replay(speedMultiplier: Double) }

    let route: PlannedRoute
    let level: ExperienceLevel
    let mode: Mode
    private(set) var cues: [Cue]
    private let signals: [Double]
    private let follower: RouteFollower
    private var scheduler = CueScheduler()
    private let speaker = Speaker()

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

    private var replayTimer: Timer?
    private var replayMeters = 0.0
    private var clock: TimeInterval = 0
    private var locationDelegate: LocationDelegate?

    var muted: Bool {
        get { speaker.isMuted }
        set { speaker.isMuted = newValue }
    }

    init(route: PlannedRoute, cache: OSMCache, features: [RoadFeature], highInjury: HighInjuryNetwork?,
         level: ExperienceLevel, mode: Mode) {
        self.route = route
        self.level = level
        self.mode = mode
        let built = CueListBuilder.build(route: route, cache: cache, features: features, highInjury: highInjury)
        let targets = route.maneuvers.filter(\.needsLaneChoice).map(\.alongMeters).sorted()
        cues = CueScheduler.plan(built, level: level, maneuverTargets: targets)
        signals = CueListBuilder.signalAlongs(line: route.polyline, cache: cache)
        follower = RouteFollower(polyline: route.polyline)
        position = route.polyline.points.first
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

    func end() {
        replayTimer?.invalidate(); replayTimer = nil
        locationDelegate?.manager.stopUpdatingLocation(); locationDelegate = nil
        speaker.stop()
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
        heading = route.polyline.bearing(atMeters: replayMeters) ?? heading
        for cue in cues where cue.targetMeters < replayMeters { scheduler.markFired(cue.id) }
        position = c
    }

    private func replaySpeed(at meters: Double) -> Double {
        let nearManeuver = route.maneuvers.contains { $0.needsLaneChoice && abs($0.alongMeters - meters) < 60 }
        if nearManeuver { return 6.7 }   // 15 mph
        let mph = cues.last { $0.targetMeters <= meters && $0.roadSpeedMph != nil }?.roadSpeedMph ?? 30
        return Double(mph) * 0.447 * 0.9
    }

    private func startLive() {
        let d = LocationDelegate { [weak self] loc in
            guard let self else { return }
            self.clock = loc.timestamp.timeIntervalSince(self.startedAt)
            self.feed(Coordinate(loc.coordinate), at: self.clock)
        }
        locationDelegate = d
        d.manager.requestWhenInUseAuthorization()
        d.manager.startUpdatingLocation()
    }

    // MARK: Each location fix

    func feed(_ location: Coordinate, at time: TimeInterval) {
        guard !isFinished, let p = follower.update(location: location, at: time) else { return }
        progress = p
        position = p.isOffRoute ? location : p.snapped
        heading = route.polyline.bearing(atMeters: p.alongMeters) ?? heading

        if p.isOffRoute {
            if lastCueText != "Off the route" {
                lastCueText = "Off the route"
                speaker.say("You are off the route. Keep driving safely, I will pick it up when you are back on it.")
            }
            return
        }

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
        if p.remainingMeters < 15 && !isFinished { end() }
    }

    private var lastLaneCue: Cue?

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

    init(onFix: @escaping (CLLocation) -> Void) {
        self.onFix = onFix
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for l in locations where l.horizontalAccuracy >= 0 && l.horizontalAccuracy < 50 { onFix(l) }
    }
}
