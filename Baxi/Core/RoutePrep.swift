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

    static func make(route: PlannedRoute, cache: OSMCache, features: [RoadFeature], highInjury: HighInjuryNetwork?) -> RoutePrep {
        let cues = CueListBuilder.build(route: route, cache: cache, features: features, highInjury: highInjury)
        return RoutePrep(routeId: route.id, cues: cues,
                         signals: CueListBuilder.signalAlongs(line: route.polyline, cache: cache),
                         speeds: CueListBuilder.speedProfile(line: route.polyline, cache: cache),
                         spots: HardSpots.find(route: route, cues: cues, features: features))
    }

    /// The cues timed for an experience level.
    func planned(for level: ExperienceLevel, route: PlannedRoute) -> [Cue] {
        CueScheduler.plan(cues, level: level, maneuverTargets: route.maneuvers.filter(\.needsLaneChoice).map(\.alongMeters).sorted())
    }
}
