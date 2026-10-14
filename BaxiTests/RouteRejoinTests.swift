import Foundation
import Testing
@testable import Baxi

struct RouteRejoinTests {
    // A 2 km route due east along 39.97 N, with a roundabout at 1,200 m and arrival at the end.
    let original: PlannedRoute = {
        let pts = (0...20).map { Coordinate(lat: 39.97, lon: -86.15 + Double($0) * 0.00117) }
        let line = Polyline(pts)
        func m(_ id: Int, _ kind: Maneuver.Kind, _ along: Double) -> Maneuver {
            Maneuver(id: id, kind: kind, direction: nil, location: line.coordinate(atMeters: along)!, alongMeters: along,
                     exitNumber: kind == .roundabout ? 2 : nil, roadName: nil, instruction: "\(kind)", laneCount: nil, validLanes: nil)
        }
        return PlannedRoute(id: "loop", name: "Loop", polyline: line,
                            maneuvers: [m(0, .depart, 0), m(1, .turn, 300), m(2, .roundabout, 1200), m(3, .arrive, line.lengthMeters)],
                            distanceMeters: line.lengthMeters, durationSeconds: 200, source: "preset")
    }()

    // The car is 200 m south of the route at 500 m along; the approach goes north to the rejoin point.
    func approach(to target: Coordinate) -> PlannedRoute {
        let start = Coordinate(lat: target.lat - 0.0018, lon: target.lon)
        let line = Polyline([start, target])
        return PlannedRoute(id: "a", name: "Loop", polyline: line,
                            maneuvers: [Maneuver(id: 0, kind: .depart, direction: nil, location: start, alongMeters: 0, exitNumber: nil,
                                                 roadName: nil, instruction: "Head north", laneCount: nil, validLanes: nil),
                                        Maneuver(id: 1, kind: .arrive, direction: nil, location: target, alongMeters: line.lengthMeters,
                                                 exitNumber: nil, roadName: nil, instruction: "Arrive", laneCount: nil, validLanes: nil)],
                            distanceMeters: line.lengthMeters, durationSeconds: 30, source: "osrm")
    }

    @Test func rejoinAimsAheadOrAtTheStart() {
        #expect(original.rejoinMeters(leftAt: 10) == 0)
        #expect(original.rejoinMeters(leftAt: 500) == 900)
        #expect(original.rejoinMeters(leftAt: 1_900) == original.polyline.lengthMeters)
    }

    @Test func joinedRouteKeepsTheRestOfTheLoop() throws {
        let at = original.rejoinMeters(leftAt: 500)
        let a = approach(to: try #require(original.polyline.coordinate(atMeters: at)))
        let joined = original.rejoined(by: a, at: at)

        // Approach length plus what was left of the original.
        let expected = a.polyline.lengthMeters + original.polyline.lengthMeters - at
        #expect(abs(joined.polyline.lengthMeters - expected) < 2)

        // The roundabout is still there, shifted to its new distance; the passed turn is gone.
        let rb = try #require(joined.maneuvers.first { $0.kind == .roundabout })
        #expect(abs(rb.alongMeters - (a.polyline.lengthMeters + 1200 - at)) < 2)
        #expect(!joined.maneuvers.contains { $0.id == 1 })
        #expect(joined.maneuvers.filter { $0.kind == .arrive }.count == 1)
        #expect(joined.maneuvers.map(\.alongMeters) == joined.maneuvers.map(\.alongMeters).sorted())
        #expect(Set(joined.maneuvers.map(\.id)).count == joined.maneuvers.count)
    }

    @Test func rejoinAtTheEndIsJustTheApproach() {
        let a = approach(to: original.polyline.points.last!)
        #expect(original.rejoined(by: a, at: original.polyline.lengthMeters) == a)
    }
}
