import Foundation

extension Maneuver {
    func shifted(by meters: Double, idOffset: Int = 0) -> Maneuver {
        Maneuver(id: id + idOffset, kind: kind, direction: direction, location: location, alongMeters: alongMeters + meters,
                 exitNumber: exitNumber, roadName: roadName, instruction: instruction, laneCount: laneCount, validLanes: validLanes)
    }
}

extension PlannedRoute {
    /// Where a reroute should aim. Before the route has started (the car is still getting to it),
    /// the start; otherwise `ahead` meters past where the car left it, so a practice loop keeps its
    /// remaining roundabouts instead of being cut short (a loop's destination is its own start).
    func rejoinMeters(leftAt along: Double, ahead: Double = 400) -> Double {
        along < 50 ? 0 : min(polyline.lengthMeters, along + ahead)
    }

    /// A route that drives `approach` (from the car to the rejoin point) and then the rest of this
    /// route from `rejoinMeters` on. Maneuvers after the rejoin point keep their ids and are shifted to
    /// the new distances; the approach's maneuvers get ids offset by a million so cue ids stay unique.
    func rejoined(by approach: PlannedRoute, at rejoinMeters: Double) -> PlannedRoute {
        guard rejoinMeters < polyline.lengthMeters - 1, let joinPoint = polyline.coordinate(atMeters: rejoinMeters) else {
            return approach
        }
        let rest = [joinPoint] + polyline.points.indices.filter { polyline.cumulative[$0] > rejoinMeters + 0.5 }.map { polyline.points[$0] }
        let approachLine = Polyline(approach.polyline.points + [joinPoint])
        let shift = approachLine.lengthMeters - rejoinMeters
        let approachManeuvers = approach.maneuvers.filter { $0.kind != .arrive }.map { $0.shifted(by: 0, idOffset: 1_000_000) }
        let restManeuvers = maneuvers.filter { $0.alongMeters > rejoinMeters + 1 && $0.kind != .depart }.map { $0.shifted(by: shift) }
        let line = Polyline(approach.polyline.points + rest)
        let restFraction = polyline.lengthMeters > 0 ? (polyline.lengthMeters - rejoinMeters) / polyline.lengthMeters : 0
        return PlannedRoute(id: id + "-rejoin", name: name, polyline: line, maneuvers: approachManeuvers + restManeuvers,
                            distanceMeters: line.lengthMeters, durationSeconds: approach.durationSeconds + durationSeconds * restFraction,
                            source: approach.source)
    }
}
