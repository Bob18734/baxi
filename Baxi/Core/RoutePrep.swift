import Foundation

/// Everything worked out from a route and the road data before a drive: the cues (not yet timed for a
/// level), where the lights are, the posted limits, and the Preview's hard spots. Built once per route,
/// off the main thread, and shared by the Routes screen, the Preview and the drive.
struct RoutePrep {
    let routeId: String
    let cues: [Cue]
    let signals: [Double]
    let speeds: [(along: Double, mph: Int)]
    let spots: [HardSpot]
    /// All-way stops on the route, where the drive's habit report checks for a full stop. Only all-way stops:
    /// at a two-way stop the map data cannot say reliably which road the sign faces.
    var habitStops: [Double] = []
    /// Stretches of the route within 150 m of a school, for the habit report's school-zone speed.
    var schoolZones: [ClosedRange<Double>] = []

    static func make(route: PlannedRoute, cache: OSMCache, features: [RoadFeature], highInjury: HighInjuryNetwork?) -> RoutePrep {
        let cues = CueListBuilder.build(route: route, cache: cache, features: features, highInjury: highInjury)
        let allWay = cache.nodes.filter { $0.tags["highway"] == "stop" && $0.tags["stop"] == "all" }.map(\.coordinate)
        return RoutePrep(routeId: route.id, cues: cues,
                         signals: CueListBuilder.signalAlongs(line: route.polyline, cache: cache),
                         speeds: CueListBuilder.speedProfile(line: route.polyline, cache: cache),
                         spots: HardSpots.find(route: route, cues: cues, features: features, cache: cache),
                         habitStops: CueListBuilder.dedupe(CueListBuilder.onRoute(allWay, line: route.polyline,
                                                                                  within: CueListBuilder.stopMatchMeters).sorted(),
                                                           within: CueListBuilder.stopPairMeters),
                         schoolZones: schoolZones(line: route.polyline, features: features))
    }

    /// Each stretch of the line that runs within 150 m of a school.
    static func schoolZones(line: Polyline, features: [RoadFeature]) -> [ClosedRange<Double>] {
        let schools = features.filter { $0.kind == .schoolZone }.map(\.coordinate)
        guard !schools.isEmpty else { return [] }
        let step = 10.0
        var zones: [ClosedRange<Double>] = [], runStart: Double?, last = 0.0
        for s in line.samples(everyMeters: step) {
            let near = schools.contains { Geo.distanceMeters($0, s.point) <= CueListBuilder.schoolMatchMeters }
            if near, runStart == nil { runStart = s.alongMeters }
            if !near, let a = runStart { zones.append(a...last); runStart = nil }
            last = s.alongMeters
        }
        if let a = runStart { zones.append(a...last) }
        return zones
    }

    /// The cues timed for an experience level.
    func planned(for level: ExperienceLevel, route: PlannedRoute) -> [Cue] {
        CueScheduler.plan(cues, level: level, maneuverTargets: Self.boundaries(route))
    }

    /// Every point where the driver is busy with a maneuver: turns and roundabouts, and also merges and
    /// ramps. The next lane change or announcement waits until the driver is through the last one, so a
    /// highway lane is never asked for while the car is still on the on-ramp.
    static func boundaries(_ route: PlannedRoute) -> [Double] {
        route.maneuvers.filter { ![.depart, .continueStraight, .arrive, .other].contains($0.kind) }.map(\.alongMeters).sorted()
    }
}
