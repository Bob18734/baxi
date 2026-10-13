import Testing
@testable import FirstRoads

struct FeatureExtractorTests {
    private func way(_ id: Int, nodes: [Int], tags: [String: String]) -> OSMWay {
        OSMWay(id: id, tags: tags, nodes: nodes, geometry: nodes.map { [39.9 + Double($0) * 0.0001, -86.1] }, lat: nil, lon: nil)
    }

    @Test func roundaboutWaysSharingNodesBecomeOneFeature() {
        let a = way(1, nodes: [10, 11, 12], tags: ["junction": "roundabout", "highway": "primary", "lanes": "2"])
        let b = way(2, nodes: [12, 13, 10], tags: ["junction": "roundabout", "highway": "primary", "lanes": "2"])
        let leg = way(3, nodes: [20, 11], tags: ["highway": "primary", "name": "E 116th St"])
        let features = FeatureExtractor.roundaboutFeatures([a, b, leg])
        #expect(features.count == 1)
        #expect(features.first?.osmIds.sorted() == [1, 2])
        #expect(features.first?.name == "E 116th St")
    }

    @Test func separateRoundaboutsStaySeparate() {
        let a = way(1, nodes: [10, 11], tags: ["junction": "roundabout", "highway": "residential"])
        let b = way(2, nodes: [30, 31], tags: ["junction": "roundabout", "highway": "residential"])
        #expect(FeatureExtractor.groupBySharedNodes([a, b]).count == 2)
    }
}
