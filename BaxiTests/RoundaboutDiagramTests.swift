import Foundation
import Testing
@testable import Baxi

struct RoundaboutDiagramTests {
    /// A route coming from the south into a 20 m circle at the origin, around it counterclockwise
    /// (south, east, north, west), leaving at `leaveDeg` (compass bearing from the middle).
    func route(leaveDeg: Double) -> (PlannedRoute, Maneuver) {
        var pts = stride(from: -200.0, through: -20, by: 20).map { TestRoute.point(metersEast: 0, metersNorth: $0) }
        let sweep = (180 - leaveDeg + 360).truncatingRemainder(dividingBy: 360)
        for s in stride(from: 10.0, through: sweep, by: 10) {
            let b = (180 - s) * .pi / 180
            pts.append(TestRoute.point(metersEast: 20 * sin(b), metersNorth: 20 * cos(b)))
        }
        let out = leaveDeg * .pi / 180
        for d in stride(from: 40.0, through: 200, by: 20) { pts.append(TestRoute.point(metersEast: d * sin(out), metersNorth: d * cos(out))) }
        let line = Polyline(pts)
        let exit = leaveDeg == 90 ? 1 : leaveDeg == 0 ? 2 : 3
        let m = Maneuver(id: 1, kind: .roundabout, direction: nil, location: TestRoute.point(metersEast: 0, metersNorth: -20),
                         alongMeters: 180, exitNumber: exit, roadName: nil, instruction: "", laneCount: nil, validLanes: nil)
        return (PlannedRoute(id: "r", name: "r", polyline: line, maneuvers: [m], distanceMeters: line.lengthMeters,
                             durationSeconds: 60, source: "test"), m)
    }

    @Test(arguments: [(90.0, 1), (0.0, 2), (270.0, 3)])
    func exitAngleFollowsTheRoad(_ leave: Double, _ exit: Int) throws {
        let (r, m) = route(leaveDeg: leave)
        let shape = try #require(RoundaboutDiagram.shape(for: m, route: r, center: TestRoute.point(metersEast: 0)))
        let off = abs(((shape.exitAngle - leave) + 540).truncatingRemainder(dividingBy: 360) - 180)
        #expect(off < 12, "exit drawn at \(shape.exitAngle), road leaves at \(leave)")
        #expect(shape.passedAngles.count == exit - 1)
    }
}
