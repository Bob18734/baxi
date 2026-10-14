import Foundation
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

    /// A road that continues through the roundabout is two legs, though both sides share a name; the two
    /// one-way carriageways of a divided road (one in, one out) are one. (The Carmel City Center
    /// roundabouts on City Center Drive and Guilford Road were counted as 2 legs before this rule.)
    @Test func throughRoadIsTwoLegsAndDividedRoadIsOne() {
        let c = (lat: 39.95, lon: -86.1)
        let r = 0.0003   // about 33 m
        func at(_ deg: Double) -> [Double] {
            let a = deg * .pi / 180
            return [c.lat + r * cos(a), c.lon + r * sin(a) / cos(c.lat * .pi / 180)]
        }
        let ring = [0.0, 10, 90, 180, 270, 350]
        let circle = OSMWay(id: 1, tags: ["junction": "roundabout", "lanes": "2"], nodes: ring.indices.map { 100 + $0 },
                            geometry: ring.map(at), lat: nil, lon: nil)
        /// `flow`: nil two-way, true one-way into the circle, false one-way out of it.
        func leg(_ id: Int, _ name: String, meets node: Int, deg: Double, into flow: Bool? = nil) -> OSMWay {
            var tags = ["highway": "tertiary", "name": name]
            if flow != nil { tags["oneway"] = "yes" }
            let nodes = flow == true ? [id, node] : [node, id]
            let far = at(deg).map { $0 + 0.001 }
            return OSMWay(id: id, tags: tags, nodes: nodes, geometry: flow == true ? [far, at(deg)] : [at(deg), far], lat: nil, lon: nil)
        }
        let legs = [leg(10, "City Center Drive", meets: 102, deg: 90), leg(11, "City Center Drive", meets: 104, deg: 270),
                    leg(12, "Guilford Road", meets: 105, deg: 350, into: true), leg(13, "Guilford Road", meets: 101, deg: 10, into: false),
                    leg(14, "Guilford Road", meets: 103, deg: 180, into: true), leg(15, "Guilford Road", meets: 103, deg: 180, into: false)]
        let result = RoundaboutClassifier.classify(RoundaboutInput(circleWays: [circle], touchingWays: legs))
        #expect(result.legs == 4)
    }
}
