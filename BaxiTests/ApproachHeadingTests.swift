import Testing
@testable import Baxi

// Partner's module. These run once ApproachHeading.isImplemented is true.
@Suite(.enabled(if: ApproachHeading.isImplemented, "ApproachHeading is still the stub"))
struct ApproachHeadingTests {
    @Test func eastboundApproachIsNinety() {
        let route = (0...10).map { TestRoute.point(metersEast: Double($0) * 50) }
        let b = ApproachHeading.bearing(route: route, spot: TestRoute.point(metersEast: 300))!
        #expect(abs(b - 90) < 1)
    }

    @Test func lookBackUsesAtLeastFortyMeters() {
        // A route that goes north for 200 m then east for 200 m. The spot is 20 m into the east leg.
        var route = (0...4).map { TestRoute.point(metersEast: 0, metersNorth: Double($0) * 50) }
        route += (1...4).map { TestRoute.point(metersEast: Double($0) * 50, metersNorth: 200) }
        let spot = TestRoute.point(metersEast: 50, metersNorth: 200)
        // Nearest point is 50 m along the east leg; walking back 40 m stays on the east leg, so bearing is about 90.
        let b = ApproachHeading.bearing(route: route, spot: spot)!
        #expect(abs(b - 90) < 1)
        // With a 120 m look-back the walk crosses the corner, so the bearing points north-east.
        let long = ApproachHeading.bearing(route: route, spot: spot, lookBackMeters: 120)!
        #expect(long > 20 && long < 70)
    }

    @Test func nilForShortRoutesAndRouteStart() {
        #expect(ApproachHeading.bearing(route: [TestRoute.point(metersEast: 0)], spot: TestRoute.point(metersEast: 0)) == nil)
        let route = (0...4).map { TestRoute.point(metersEast: Double($0) * 50) }
        #expect(ApproachHeading.bearing(route: route, spot: TestRoute.point(metersEast: 0)) == nil)
    }
}
