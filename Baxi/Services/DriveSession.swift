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
    /// Where to change lanes on this route, for the map and the lane panel. Rebuilt with the cues.
    private(set) var laneZones: [LaneZone] = []
    /// Said once after the start line when the weather may affect the roads (from WeatherService).
    var weatherLine: String?
    /// Each zone's stretch of road, ready for the map (built once, not on every fix).
    private(set) var laneZoneCoordinates: [String: [CLLocationCoordinate2D]] = [:]

    /// The lane zone the car is in or about to enter.
    var activeLaneZone: LaneZone? { LaneZones.active(laneZones, at: progress?.alongMeters ?? -1_000) }
    /// 0 at the start of the active zone, 1 where the driver must be in the lane.
    var laneZoneProgress: Double { activeLaneZone.map { LaneZones.progress($0, at: progress?.alongMeters ?? 0) } ?? 0 }

    /// "Just directions" (Settings > Voice): only what to do at each turn, lane, roundabout, ramp, railroad
    /// crossing and arrival. Speed, school, stop-sign, crash and glare lines are left out; the screen still shows them.
    static let detailKey = "voiceDetail"
    static func filtered(_ cues: [Cue]) -> [Cue] {
        guard UserDefaults.standard.string(forKey: detailKey) == "directions" else { return cues }
        let quiet: Set<CueKind> = [.speedChange, .schoolZone, .stopSign, .crashCorridor, .glare]
        return cues.map { c in
            guard quiet.contains(c.kind) else { return c }
            var c = c; c.fireAtMeters = nil; return c
        }
    }

    private func rebuildLaneZones() {
        let circles = features.filter { [.singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout].contains($0.kind) }
        roundaboutShapes = Dictionary(uniqueKeysWithValues: route.maneuvers.compactMap { m -> (Int, RoundaboutShape)? in
            guard m.kind == .roundabout else { return nil }
            let center = circles.min { Geo.distanceMeters($0.coordinate, m.location) < Geo.distanceMeters($1.coordinate, m.location) }
                .flatMap { Geo.distanceMeters($0.coordinate, m.location) <= 80 ? $0.coordinate : nil }
            return RoundaboutDiagram.shape(for: m, route: route, center: center).map { (m.id, $0) }
        })
        laneZones = LaneZones.build(cues: cues, route: route)
        laneZoneCoordinates = Dictionary(uniqueKeysWithValues: laneZones.map {
            ($0.id, route.polyline.slice(from: $0.startMeters, to: $0.endMeters).map(\.clLocation))
        })
    }
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
    private(set) var spokenLog: [(meters: Double, text: String)] = []
    private(set) var isFinished = false
    /// One speed sample per fix on the route, for the habit report. Along positions on a later route
    /// (after a reroute) are shifted by `alongOffset`, so places on different routes never mix.
    @ObservationIgnored private var samples: [SpeedSample] = []
    @ObservationIgnored private var habitStops: [Double] = []
    @ObservationIgnored private var schoolZones: [ClosedRange<Double>] = []
    @ObservationIgnored private var mergeAlongs: [Double] = []
    @ObservationIgnored private var alongOffset = 0.0
    private static let routeOffsetMeters = 10_000_000.0
    /// The latest GPS speed, m/s; negative or nil when unknown.
    private var lastSpeedMps: Double?
    /// How the drive went, worked out when it ends. nil while driving, or when it was too short to judge.
    private(set) var habits: HabitReport?
    /// True while the car is following the route (not still heading to its start, not off it), so the speed
    /// pill compares against a limit on the road the car is actually on.
    var isOnRoute: Bool { (mode != .live || hasReachedRoute) && progress?.isOffRoute == false && (progress?.crossTrackMeters ?? .infinity) <= RouteFollower.offRouteMeters }
    /// The car's speed for the speed pill, nil when the GPS does not know it.
    var currentMph: Int? { lastSpeedMps.flatMap { $0 >= 0 ? Int(($0 * DriveHabits.mphPerMps).rounded()) : nil } }
    /// The replay's speed every `replayStepMeters`: posted limit with smooth slowing for turns and stops.
    @ObservationIgnored private var replayProfile: [Double] = []
    /// Where the replay comes to a stop on the current route, and how long it still waits at the one it is at.
    @ObservationIgnored private var replayStops: [Double] = []
    @ObservationIgnored private var replayWait = 0.0
    static let replayStopSeconds = 2.0
    static let replayStepMeters = 5.0
    private(set) var startedAt = Date()
    private var started = false
    private(set) var endedAt: Date?
    static let locationOffText = "Location is off. Turn it on in Settings."
    static let farFromRouteText = "You're far from this route. Drive to it, or replay it from Routes."
    static let farFromRouteMeters = 20_000.0
    static let rerouteFailedText = "No connection for a new route. Head back to the blue line."
    /// False on a live drive until the first location fix arrives.
    private(set) var hasFix = false
    /// Fixes are arriving but too rough to follow a road (Precise Location off, or indoors).
    private(set) var coarseFixes = false
    /// Where reroutes come from; a test swaps in one that fails.
    @ObservationIgnored var router: @Sendable (Coordinate, Coordinate, String) async throws -> PlannedRoute = {
        try await RouteService.route(from: $0, to: $1, name: $2)
    }
    private var saidRerouteFailed = false
    private(set) var isRerouting = false
    private(set) var rerouteCount = 0
    /// Meters driven on routes replaced by a reroute.
    private var metersBeforeReroute = 0.0
    /// Where on the first route the drive actually began (a replay can skip ahead, a live drive can
    /// start partway along), so the distance driven does not count the part before it.
    private var firstAlongMeters: Double?
    /// Maneuvers the car has gone through on this drive, for the Arrived screen.
    private(set) var passedManeuvers: [Maneuver] = []
    /// Meters driven on roads posted 45 mph or more, for the practice tally.
    private(set) var fastMeters = 0.0
    /// The skills this drive practiced, from what was actually driven.
    var practiced: SkillCounts { Practice.count(maneuvers: passedManeuvers, features: features, fastMeters: fastMeters) }
    private var passedAlong = 0.0
    /// More progress than this in one location fix is a jump along the route, not driving.
    static let maxJumpMeters = 250.0
    private var lastFeedTime: TimeInterval?
    private var lastFixOnRoute = true
    private var lastRerouteAttempt: TimeInterval = -.infinity
    /// False until the car is first within 30 m of the route; a live drive started from somewhere
    /// else (a preset loop started from home) is guided to the route's start right away.
    private var hasReachedRoute = false

    private var replayTimer: Timer?
    /// False until the start line has been said; the replay car waits until then.
    private var replayDeparted = false
    /// Real seconds the replay has been held to real speed by one stretch of talking.
    private var replayTalkSeconds = 0.0
    private var replayMultiplierNow = 1.0
    static let replayRampDown = 0.4
    static let replayRampUp = 1.2
    /// Longer than any line Baxi says (with a line queued behind it); past this the voice is not waited on.
    static let replayTalkLimitSeconds = 25.0
    private var replayMeters = 0.0
    private var clock: TimeInterval = 0
    private var locationDelegate: LocationDelegate?

    var muted = false {
        didSet { speaker.isMuted = muted }
    }

    init(route: PlannedRoute, cache: OSMCache, features: [RoadFeature], highInjury: HighInjuryNetwork?,
         level: ExperienceLevel, mode: Mode, speaker: SpeechOutput = Speaker(), prep: RoutePrep? = nil) {
        self.speaker = speaker
        self.route = route
        self.routeCoordinates = route.polyline.points.map(\.clLocation)
        self.level = level
        self.mode = mode
        self.cache = cache
        self.features = features
        self.highInjury = highInjury
        startCoordinate = route.polyline.points.first
        let p = prep.flatMap { $0.routeId == route.id ? $0 : nil }
            ?? RoutePrep.make(route: route, cache: cache, features: features, highInjury: highInjury)
        (cues, signals, speeds) = (Self.filtered(p.planned(for: level, route: route)), p.signals, p.speeds)
        follower = RouteFollower(polyline: route.polyline)
        rebuildLaneZones()
        position = route.polyline.points.first
        addHabitPlaces(p)
    }

    /// The stops, school zones and merges of the route now driven, shifted to this route's offset.
    private func addHabitPlaces(_ p: RoutePrep) {
        habitStops += p.habitStops.map { $0 + alongOffset }
        schoolZones += p.schoolZones.map { ($0.lowerBound + alongOffset)...($0.upperBound + alongOffset) }
        mergeAlongs += DriveHabits.judgedMerges(route.maneuvers).map { $0 + alongOffset }
        let stopsHere = p.habitStops + cues.filter { $0.kind == .stopSign }.map(\.targetMeters)
        if case .replay = mode {
            replayProfile = Self.replayProfile(route: route, speeds: speeds, stops: stopsHere)
            replayStops = Array(Set(stopsHere.map { ($0 * 10).rounded() / 10 })).sorted()
        }
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
        let shown: Set<CueKind> = [.schoolZone, .crashCorridor, .railroad, .glare]
        return cues.first { shown.contains($0.kind) && along >= $0.targetMeters - 250 && along <= $0.targetMeters + ($0.kind == .railroad ? 30 : 500) }
    }

    /// Each roundabout's shape, for the diagram on the sign (built with the cues).
    private(set) var roundaboutShapes: [Int: RoundaboutShape] = [:]

    /// 0 when the next maneuver's instruction is first given, 1 at the maneuver: the bar on the sign.
    var nextManeuverProgress: Double? {
        guard let m = nextManeuver, let along = progress?.alongMeters,
              let start = cues.first(where: { $0.maneuverId == m.id && $0.kind != .laneChange && $0.kind != .signal })?.fireAtMeters,
              along >= start, m.alongMeters > start else { return nil }
        return min(1, (along - start) / (m.alongMeters - start))
    }

    /// The maneuver right after the next one, when it comes within 300 m of it: "Then turn left".
    var thenManeuver: Maneuver? {
        guard let m = nextManeuver else { return nil }
        return route.maneuvers.first { $0.alongMeters > m.alongMeters + 1 && $0.kind != .continueStraight && $0.kind != .depart }
            .flatMap { $0.alongMeters - m.alongMeters <= 300 && $0.kind != .arrive ? $0 : nil }
    }

    // MARK: The next maneuver, for the big card

    /// The lanes are shown from this far before a maneuver that has lane data (or from its first lane line,
    /// when that comes earlier), so the driver sees them while there is still room to move over.
    static let lanesAheadMeters = 800.0

    /// The lanes at the next maneuver, the one(s) to be in lit, while it is close: from the approach's
    /// turn:lanes tag, the router's lane data, or, at a roundabout mapped with two or more lanes, the standard
    /// markings. nil where none of those exists, and while off the route. The phone cannot tell which lane the
    /// car is in, so this never marks one as "you".
    var upcomingLanes: LaneStrip? {
        guard isOnRoute, let m = nextManeuver, let along = progress?.alongMeters else { return nil }
        let mine = cues.filter { $0.maneuverId == m.id && $0.laneStrip != nil }
        // The lane line's strip first (it marks the one lane asked for), as Preview does.
        guard let strip = (mine.first { $0.kind == .laneChange } ?? mine.first)?.laneStrip, strip.laneCount >= 2 else { return nil }
        let from = min(m.alongMeters - Self.lanesAheadMeters, mine.compactMap(\.fireAtMeters).min() ?? .infinity)
        return along >= from ? strip : nil
    }

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
        guard !started else { return }
        started = true
        startedAt = Date()
        // Low sun depends on when the drive happens, so its cues are added now, from where the car is.
        let from = progress?.alongMeters ?? 0
        let glare = CueScheduler.plan(SunGlare.cues(SunGlare.stretches(route: route, start: startedAt, from: from), speeds: speeds),
                                      level: level, maneuverTargets: RoutePrep.boundaries(route))
        cues += Self.filtered(glare)
        for c in glare where (c.fireAtMeters ?? 0) < from { scheduler.markFired(c.id) }
        speaker.say(Line.start)
        if let weatherLine { speaker.say(weatherLine); spokenLog.append((0, weatherLine)) }
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
        // The report first: saving the drive is triggered by isFinished and stores the report with it.
        habits = DriveHabits.report(samples: samples, stopSignAlongs: habitStops, schoolZones: schoolZones,
                                    mergeAlongs: mergeAlongs, isDemo: mode != .live)
        isFinished = true
    }

    /// Replays the route at a believable speed: the posted limit where known, else 30 mph,
    /// slowed to 15 mph near roundabouts and turns. `multiplier` speeds the clock for testing.
    private func startReplay(multiplier: Double) {
        // Ten updates a second: the car glides on screen instead of stepping.
        let tick = 0.1
        replayTimer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            self?.advanceReplay(tick: tick, multiplier: multiplier)
        }
    }

    /// One replay timer tick (internal so tests can run a 4x replay without a timer).
    /// The car moves in steps no longer than the profile's cells, so at 4x it still slows into a stop sign the
    /// way the profile says, and the speed reported is the speed where it ends up.
    ///
    /// While Baxi is talking the replay runs at real speed, whatever the multiplier: the voice cannot talk four
    /// times faster, so at a steady 4x most instructions were still being said when the car reached the turn
    /// (35 across the demos, `swift run baxi-demo-check`). The car also waits at the start until the start line
    /// has been said, as a driver would. Muted, the car still slows for as long as the line would have taken, so
    /// the sign's text keeps the same pace. A voice that never finishes (an interrupted line the system never
    /// reports) is waited on for at most `replayTalkLimitSeconds`, so a demo can never stall.
    func advanceReplay(tick: Double, multiplier requested: Double) {
        let talking = speaker.isSpeaking || (muted && clock < (scheduler.speechEndsAt ?? 0))
        replayTalkSeconds = talking ? replayTalkSeconds + tick : 0
        let waitForVoice = talking && replayTalkSeconds < Self.replayTalkLimitSeconds
        if !replayDeparted {
            guard !waitForVoice else { clock += tick; return }
            replayDeparted = true
        }
        // Speed changes ease in rather than switch: dropping to real speed for a line takes `replayRampDown`
        // seconds, getting back up to the demo's speed `replayRampUp`, so the car never lurches on screen.
        let target = waitForVoice ? 1 : requested
        let rampSeconds = target < replayMultiplierNow ? Self.replayRampDown : Self.replayRampUp
        let step = abs(requested - 1) * tick / max(tick, rampSeconds)
        replayMultiplierNow = target < replayMultiplierNow ? max(target, replayMultiplierNow - step) : min(target, replayMultiplierNow + step)
        let multiplier = replayMultiplierNow
        var left = tick * multiplier
        let length = route.polyline.lengthMeters
        while left > 0, replayMeters < length {
            if replayWait > 0 {
                // Stopped at a stop sign, counting to two.
                let w = min(left, replayWait); replayWait -= w; left -= w; continue
            }
            let v = replaySpeed(at: replayMeters)
            let dt = min(left, Self.replayStepMeters / v)
            let next = min(length, replayMeters + v * dt)
            if let stop = replayStops.first(where: { $0 > replayMeters && $0 <= next }) {
                left -= (stop - replayMeters) / v
                replayMeters = stop
                replayWait = Self.replayStopSeconds
            } else {
                replayMeters = next
                left -= dt
            }
        }
        clock += tick * multiplier
        let speed = replayWait > 0 ? 0 : replaySpeed(at: replayMeters)
        if let c = route.polyline.coordinate(atMeters: replayMeters) { feed(c, at: clock, speedMps: speed) }
        if replayMeters >= route.polyline.lengthMeters { replayTimer?.invalidate(); if !isFinished { end() } }
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
            let v = replaySpeed(at: meters)
            t += step / v
            if let c = route.polyline.coordinate(atMeters: meters) { feed(c, at: t, speedMps: v) }
        }
        if !isFinished { end() }
        return spokenLog
    }

    /// The profile's speed at `meters`, read between its cells so it changes smoothly. Speed squared is what
    /// changes evenly with distance under steady braking, so that is what is blended.
    private func replaySpeed(at meters: Double) -> Double {
        guard !replayProfile.isEmpty else { return 6.7 }
        let x = max(0, meters / Self.replayStepMeters)
        let i = min(replayProfile.count - 1, Int(x)), j = min(replayProfile.count - 1, i + 1)
        let f = x - Double(Int(x))
        let a = replayProfile[i], b = replayProfile[j]
        return max(0.4, (a * a * (1 - f) + b * b * f).squareRoot())
    }

    /// A careful driver's speed along the route, for replays: 90% of the posted limit (30 mph where unknown),
    /// 15 mph through turns and roundabouts, a full stop at stop signs, and never braking or speeding up
    /// harder than an easy, comfortable rate, so a replay's habit report is clean.
    static func replayProfile(route: PlannedRoute, speeds: [(along: Double, mph: Int)], stops: [Double]) -> [Double] {
        let step = replayStepMeters, decel = 2.0, accel = 2.5
        let n = Int(route.polyline.lengthMeters / step) + 2
        let turns = route.maneuvers.filter(\.needsLaneChoice).map(\.alongMeters)
        var v = (0..<n).map { i -> Double in
            let m = Double(i) * step
            if stops.contains(where: { abs($0 - m) <= step }) { return 0.4 }   // crawl the last few meters
            if turns.contains(where: { abs($0 - m) < 60 }) { return 6.7 }   // 15 mph
            // A limit of 0 (a mapping slip) or none: 30 mph.
            let mph = CueListBuilder.speed(at: m, in: speeds).flatMap { $0 > 0 ? $0 : nil } ?? 30
            return Double(mph) * 0.44704 * 0.9
        }
        v[0] = min(v[0], 2)
        for i in stride(from: n - 2, through: 0, by: -1) { v[i] = min(v[i], (v[i + 1] * v[i + 1] + 2 * decel * step).squareRoot()) }
        for i in 1..<n { v[i] = min(v[i], (v[i - 1] * v[i - 1] + 2 * accel * step).squareRoot()) }
        return v
    }

    private func startLive() {
        var previous: (at: Coordinate, t: TimeInterval)?
        let d = LocationDelegate(onFix: { [weak self] loc in
            guard let self else { return }
            self.clock = loc.timestamp.timeIntervalSince(self.startedAt)
            let here = Coordinate(loc.coordinate)
            let speed = Self.speedFromFixes(reported: loc.speed, from: previous?.at, at: previous?.t ?? 0, to: here, at: self.clock)
            previous = (here, self.clock)
            self.feed(here, at: self.clock, speedMps: speed ?? -1)
        }, onDenied: { [weak self] in
            guard let self, self.lastCueText != Self.locationOffText else { return }
            self.lastCueText = Self.locationOffText
            self.speaker.say(Line.locationOff)
        }, onCoarseFix: { [weak self] in
            guard let self, !self.hasFix else { return }
            self.coarseFixes = true
        })
        locationDelegate = d
        d.manager.requestWhenInUseAuthorization()
        d.manager.startUpdatingLocation()
    }

    // MARK: Each location fix

    /// `speedMps`: the GPS speed (negative when unknown), or the replay's speed; nil when not known at all.
    func feed(_ location: Coordinate, at time: TimeInterval, speedMps: Double? = nil) {
        guard !isFinished else { return }
        hasFix = true
        if lastCueText == Self.locationOffText { lastCueText = "" }
        lastSpeedMps = speedMps
        // A held fix (a far jump waiting for confirmation) changes nothing, not even the time of the last fix.
        guard let p = follower.update(location: location, at: time), !p.isHeld else { return }
        if p.crossTrackMeters < 30 { hasReachedRoute = true }
        if mode == .live, !hasReachedRoute, p.crossTrackMeters > RouteFollower.offRouteMeters {
            // Still heading to the route: no progress, no cues, until the car is on it.
            position = location
            // Nowhere near the route (another town): a new route to its start is not what the driver needs.
            if p.crossTrackMeters > Self.farFromRouteMeters {
                lastCueText = Self.farFromRouteText
                return
            }
            if lastCueText != Self.rerouteFailedText { lastCueText = "Getting you to the start" }
            if !saidGetToStart { saidGetToStart = true; speaker.say(Line.getToStart) }
            if !isRerouting, time - lastRerouteAttempt > 30 { reroute(from: location, at: time) }
            return
        }
        if progress == nil {
            if firstAlongMeters == nil { firstAlongMeters = p.alongMeters }
            passedAlong = p.alongMeters
        }
        progress = p
        // After a GPS gap (a bridge, a dead zone) the car may legitimately be far ahead: up to 40 m/s
        // (about 90 mph) for the time the signal was gone counts as driven, not as a shortcut.
        // Only if the car was on the route when the signal went, at no more than 1.3 times the posted
        // limit (25 m/s where untagged), and for at most 60 s of gap.
        let limit = (CueListBuilder.speed(at: passedAlong, in: speeds)).map { Double($0) * 0.44704 * 1.3 } ?? 25
        let gapAllowance = lastFeedTime.map { last in lastFixOnRoute ? min(60, max(0, time - last - 2)) * limit : 0 } ?? 0
        lastFeedTime = time
        lastFixOnRoute = p.crossTrackMeters <= RouteFollower.offRouteMeters
        if p.alongMeters - passedAlong > Self.maxJumpMeters + gapAllowance {
            // The car joined the route further along (another road, a shortcut): what it skipped was
            // neither driven nor handled.
            firstAlongMeters = (firstAlongMeters ?? 0) + (p.alongMeters - passedAlong)
        } else {
            passedManeuvers += route.maneuvers.filter { $0.alongMeters > passedAlong && $0.alongMeters <= p.alongMeters }
            if p.alongMeters > passedAlong, (CueListBuilder.speed(at: p.alongMeters, in: speeds) ?? 0) >= Practice.fastMph {
                fastMeters += p.alongMeters - passedAlong
            }
        }
        passedAlong = max(passedAlong, p.alongMeters)
        position = p.crossTrackMeters > RouteFollower.offRouteMeters ? location : p.snapped
        heading = route.polyline.bearing(atMeters: p.alongMeters) ?? heading

        if p.isOffRoute {
            // After a failed reroute its message stays up until the car is back or a new route comes.
            if lastCueText != "Off the route", lastCueText != Self.rerouteFailedText {
                lastCueText = "Off the route"
                speaker.say(Line.offRoute)
            }
            if mode == .live, !isRerouting, time - lastRerouteAttempt > 30 { reroute(from: location, at: time) }
            return
        }

        // The timeout filters GPS noise before declaring a missed route. It does not make
        // instructions on the old line valid while the car is already away from that line.
        guard p.crossTrackMeters <= RouteFollower.offRouteMeters else { return }

        if lastCueText == "Off the route" || lastCueText == Self.rerouteFailedText { lastCueText = "" }
        saidRerouteFailed = false
        if let v = speedMps {
            samples.append(SpeedSample(t: time, along: p.alongMeters + alongOffset, mps: v,
                                       limitMph: CueListBuilder.speed(at: p.alongMeters, in: speeds)))
        }

        if let cue = scheduler.due(from: cues, alongMeters: p.alongMeters, now: time) {
            let lights = lightsFor(cue, along: p.alongMeters)
            var spoken = cue.spoken(lights: lights, metersAway: cue.targetMeters - p.alongMeters)
            if cue.spokenTemplate.contains("{reminder}"), !saidRoundaboutReminder {
                // Once per drive, at the first two-lane roundabout.
                saidRoundaboutReminder = true
                spoken += Line.roundaboutReminder
            }
            lastCue = cue
            lastCueText = cue.card(lights: lights)
            spokenLog.append((p.alongMeters, spoken))
            speaker.say(spoken, chime: true)
            // The line as actually said (light counts filled in), at the voice speed the user chose. A replay runs
            // its clock at real speed while a line is being said (advanceReplay), so a line lasts the same on the
            // session clock as in real time.
            let rate = UserDefaults.standard.object(forKey: Speaker.rateKey) as? Double ?? 1
            scheduler.noteSpeech(spoken, at: time, rate: rate)
        }
        // Within 30 m of the end counts as there: GPS is often 10 to 20 m off, and people park short.
        // A replay has no GPS error, so it drives through every turn first (the practice routes end with a
        // left into the lot 24 m before the pin, which "arrived" used to swallow).
        let turnsLeft = mode != .live && route.maneuvers.contains { $0.kind != .arrive && $0.alongMeters > p.alongMeters + 5 }
        if p.remainingMeters < Self.arrivalMeters, !turnsLeft, previousAlong > route.polyline.lengthMeters - 300, !isFinished {
            if let arrive = cues.first(where: { $0.kind == .arrive }) { scheduler.markFired(arrive.id); lastCue = arrive }
            // The car is there: credit the last few meters and any turn in them, as if it drove to the pin.
            let destination = route.polyline.lengthMeters
            passedManeuvers += route.maneuvers.filter { $0.alongMeters > passedAlong && $0.alongMeters <= destination && $0.kind != .arrive }
            arrivalCreditMeters = max(0, destination - p.alongMeters)
            passedAlong = destination
            lastCueText = "Arrived"
            spokenLog.append((p.alongMeters, Line.arrived))
            speaker.say(Line.arrived, chime: true)
            end(stopSpeech: false)
        }
        previousAlong = p.alongMeters
    }

    static let arrivalMeters = 30.0

    /// The lines Baxi says outside the cue list, in one place so the recorded voice covers them all.
    enum Line {
        static let start = "Here we go. I'll tell you about each turn early."
        static let locationOff = "Location is off for Baxi. Pull over, then turn it on in Settings."
        static let getToStart = "First, let's get you to the start of the route."
        static let offRoute = "You're off the route. Keep driving, I'm finding a new way."
        static let arrived = "You've arrived"
        static let rerouteFailed = "I can't get a new route right now. Head back to the blue line when it's safe."
        static let newRoute = "New route"
        static let roundaboutReminder = ". No lane changes inside the roundabout"
        static let all = [start, locationOff, getToStart, offRoute, arrived, rerouteFailed, newRoute]
    }
    private var saidRoundaboutReminder = false
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
            guard let router = self?.router else { return }
            let approach = try? await router(location, target, original.name)
            guard let self, !self.isFinished else { return }
            guard let approach else {
                // Keep trying every 30 s, but tell the driver now what to do meanwhile, once per stretch off the route.
                self.isRerouting = false
                self.lastCueText = Self.rerouteFailedText
                if !self.saidRerouteFailed {
                    self.saidRerouteFailed = true
                    self.speaker.say(Line.rerouteFailed)
                }
                return
            }
            let new = original.rejoined(by: approach, at: rejoin)
            // Cue building takes a moment; do it off the main thread so fixes keep flowing meanwhile.
            let (cache, features, hin) = (self.cache, self.features, self.highInjury)
            let prep = await Task.detached(priority: .userInitiated) {
                RoutePrep.make(route: new, cache: cache, features: features, highInjury: hin)
            }.value
            guard !self.isFinished else { return }
            self.isRerouting = false
            self.install(new, prep: prep)
            // The next instruction comes from the cues at its usual distance, not all at once here.
            self.speaker.say(Line.newRoute)
        }
    }

    /// Replace the route while retaining completed distance, not its untraveled starting offset.
    /// Internal so tests can exercise reroute transitions without a network request.
    func install(_ new: PlannedRoute, prep: RoutePrep? = nil) {
        guard !isFinished else { return }
        metersBeforeReroute = drivenMeters
        firstAlongMeters = nil
        passedAlong = 0
        previousAlong = 0
        route = new
        let p = prep.flatMap { $0.routeId == new.id ? $0 : nil }
            ?? RoutePrep.make(route: new, cache: cache, features: features, highInjury: highInjury)
        (cues, signals, speeds) = (Self.filtered(p.planned(for: level, route: new)), p.signals, p.speeds)
        rebuildLaneZones()
        alongOffset += Self.routeOffsetMeters
        addHabitPlaces(p)
        follower = RouteFollower(polyline: new.polyline)
        scheduler = CueScheduler()
        progress = nil
        lastCue = nil
        lastFeedTime = nil; lastFixOnRoute = true
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

    /// The car's speed at a fix: the GPS's own when it knows it, else the distance from the previous fix over the
    /// time between them (iOS often reports -1 while the car is stopped, which is exactly when a stop is judged).
    static func speedFromFixes(reported: Double, from prev: Coordinate?, at t0: TimeInterval, to here: Coordinate,
                               at t1: TimeInterval) -> Double? {
        if reported >= 0 { return reported }
        guard let prev, t1 - t0 > 0, t1 - t0 <= 5 else { return nil }
        return Geo.distanceMeters(prev, here) / (t1 - t0)
    }

    /// Only a real supervised drive counts toward the 50 hours: live, at least a minute, and the car moved.
    static let minLoggedMeters = 200.0
    static func shouldLog(mode: Mode, seconds: TimeInterval, meters: Double) -> Bool {
        mode == .live && seconds >= 60 && meters >= minLoggedMeters
    }

    var minutes: Double { ((endedAt ?? Date()).timeIntervalSince(startedAt)) / 60 }
}

private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    let onFix: (CLLocation) -> Void
    let onDenied: () -> Void
    let onCoarseFix: () -> Void

    init(onFix: @escaping (CLLocation) -> Void, onDenied: @escaping () -> Void, onCoarseFix: @escaping () -> Void) {
        self.onFix = onFix
        self.onDenied = onDenied
        self.onCoarseFix = onCoarseFix
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
        // Allowed from Settings mid-drive: updates stopped with the denial, so ask for them again.
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // iOS often hands over a cached fix from minutes ago first; it would place the car where it was.
        var usable = false
        for l in locations where l.horizontalAccuracy >= 0 && l.horizontalAccuracy < 50
            && abs(l.timestamp.timeIntervalSinceNow) < 10 { usable = true; onFix(l) }
        if !usable, locations.contains(where: { $0.horizontalAccuracy >= 50 }) { onCoarseFix() }
    }
}
