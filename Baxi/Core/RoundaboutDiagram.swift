import Foundation

/// The shape of one roundabout as the driver will meet it, for the small diagram on the Drive sign:
/// the driver enters at the bottom, goes around counterclockwise (US), passes `passed` exits and leaves
/// at `exitAngle`. Angles are degrees clockwise from straight ahead: 0 straight on, 90 right, 270 left.
struct RoundaboutShape: Equatable {
    let exitNumber: Int
    let exitAngle: Double
    /// Exits passed before the driver's, spread around the circle between entry and exit.
    let passedAngles: [Double]
}

enum RoundaboutDiagram {
    /// Worked out from the route line itself: where it comes into the circle and where it leaves it,
    /// as seen from the circle's middle. nil when the route does not clearly leave the circle.
    static func shape(for m: Maneuver, route: PlannedRoute, center: Coordinate?) -> RoundaboutShape? {
        guard m.kind == .roundabout, let exit = m.exitNumber else { return nil }
        let line = route.polyline
        guard let entry = line.coordinate(atMeters: max(0, m.alongMeters - 25)),
              let atCircle = line.coordinate(atMeters: m.alongMeters) else { return nil }
        // The circle's middle: the mapped roundabout when there is one, else a point just past the entry.
        let c = center ?? line.coordinate(atMeters: m.alongMeters + 20) ?? atCircle
        let radius = max(12, Geo.distanceMeters(c, atCircle))
        // The first point after the entry, past the circle's edge, is on the exit road.
        var leave: Coordinate?
        var along = m.alongMeters + 10
        while along < m.alongMeters + 400, let p = line.coordinate(atMeters: along) {
            if Geo.distanceMeters(c, p) > radius + 20 { leave = p; break }
            along += 5
        }
        guard let leave else { return nil }
        let travel = Geo.bearingDegrees(from: entry, to: c)                      // direction of travel into the circle
        let exitAngle = normalized(Geo.bearingDegrees(from: c, to: leave) - travel)
        // Counterclockwise from the entry (at 180) to the exit; the exits passed sit evenly between.
        let sweep = normalized(180 - exitAngle)
        let sweepOrFull = sweep == 0 ? 360 : sweep
        let passed = (0..<max(0, exit - 1)).map { i in normalized(180 - sweepOrFull * Double(i + 1) / Double(exit)) }
        return RoundaboutShape(exitNumber: exit, exitAngle: exitAngle, passedAngles: passed)
    }

    static func normalized(_ deg: Double) -> Double { (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
}
