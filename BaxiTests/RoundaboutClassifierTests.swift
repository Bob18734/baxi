import Testing
@testable import Baxi

// Partner's module. These run once RoundaboutClassifier.isImplemented is true.
@Suite(.enabled(if: RoundaboutClassifier.isImplemented, "RoundaboutClassifier is still the stub"))
struct RoundaboutClassifierTests {
    func way(_ id: Int, _ tags: [String: String]) -> OSMWay {
        OSMWay(id: id, tags: tags, nodes: [id, id + 1], geometry: [[39.95, -86.1], [39.9501, -86.1]], lat: nil, lon: nil)
    }

    @Test func lanesIsTheMaximumTag() {
        let r = RoundaboutClassifier.classify(RoundaboutInput(
            circleWays: [way(1, ["junction": "roundabout", "lanes": "1"]), way(2, ["junction": "roundabout", "lanes": "2"])],
            touchingWays: []))
        #expect(r.lanes == 2 && r.lanesTagged && r.classification == .multiLane)
    }

    @Test func untaggedGuessesOneLane() {
        let r = RoundaboutClassifier.classify(RoundaboutInput(circleWays: [way(1, ["junction": "roundabout"])], touchingWays: []))
        #expect(r.lanes == 1 && !r.lanesTagged && r.classification == .singleLane)
    }

    @Test func legsCountDistinctNamesAndSkipPaths() {
        let r = RoundaboutClassifier.classify(RoundaboutInput(
            circleWays: [way(1, ["junction": "roundabout", "lanes": "1"])],
            touchingWays: [way(10, ["highway": "primary", "name": "E 116th St"]),
                           way(11, ["highway": "primary", "name": "E 116th St"]),      // other carriageway, same name
                           way(12, ["highway": "secondary", "name": "Hazel Dell Pkwy"]),
                           way(13, ["highway": "residential"]),                        // unnamed: counts by id
                           way(14, ["highway": "footway"]),
                           way(15, ["highway": "service"])]))
        #expect(r.legs == 3)
    }

    @Test func rampLegMakesAnInterchange() {
        let r = RoundaboutClassifier.classify(RoundaboutInput(
            circleWays: [way(1, ["junction": "roundabout", "lanes": "2"])],
            touchingWays: [way(10, ["highway": "motorway_link"]), way(11, ["highway": "primary", "name": "E 116th St"])]))
        #expect(r.classification == .interchange && r.lanes == 2)
    }
}
