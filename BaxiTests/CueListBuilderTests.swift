import Testing
@testable import Baxi

/// A synthetic drive on the 2 km test line: 45 mph for the first kilometer, 30 after; a signal at
/// 400 m and at 800 m; a right turn at 1000 m with a tagged approach; a school 100 m off the road at 1500 m.
struct CueListBuilderTests {
    static func way(_ id: Int, from: Double, to: Double, tags: [String: String]) -> OSMWay {
        let pts = stride(from: from, through: to, by: 100.0).map { TestRoute.point(metersEast: $0) }
        return OSMWay(id: id, tags: tags, nodes: pts.indices.map { id * 100 + $0 },
                      geometry: pts.map { [$0.lat, $0.lon] }, lat: nil, lon: nil)
    }

    static var cache: OSMCache {
        let fast = way(1, from: 0, to: 1000, tags: ["highway": "primary", "maxspeed": "45 mph", "name": "E 116th St"])
        let slow = way(2, from: 1000, to: 2000, tags: ["highway": "secondary", "maxspeed": "30 mph", "name": "Main St"])
        let approach = way(3, from: 900, to: 1000, tags: ["highway": "primary", "turn:lanes": "left|through|through;right"])
        let s1 = TestRoute.point(metersEast: 400), s1b = TestRoute.point(metersEast: 410, metersNorth: 8), s2 = TestRoute.point(metersEast: 800)
        let stop = TestRoute.point(metersEast: 1600)
        return OSMCache(source: "test", bbox: "", fetched: "", ways: [fast, slow, approach], nodes: [
            OSMNode(id: 11, tags: ["highway": "traffic_signals"], lat: s1.lat, lon: s1.lon),
            OSMNode(id: 12, tags: ["highway": "traffic_signals"], lat: s1b.lat, lon: s1b.lon),
            OSMNode(id: 13, tags: ["highway": "traffic_signals"], lat: s2.lat, lon: s2.lon),
            OSMNode(id: 14, tags: ["highway": "stop"], lat: stop.lat, lon: stop.lon),
        ])
    }

    static var route: PlannedRoute {
        let turn = Maneuver(id: 1, kind: .turn, direction: .right, location: TestRoute.point(metersEast: 1000), alongMeters: 1000,
                            exitNumber: nil, roadName: "Main St", instruction: "Turn right onto Main St", laneCount: nil, validLanes: nil)
        let arrive = Maneuver(id: 2, kind: .arrive, direction: nil, location: TestRoute.point(metersEast: 2000), alongMeters: 2000,
                              exitNumber: nil, roadName: nil, instruction: "Arrive", laneCount: nil, validLanes: nil)
        return PlannedRoute(id: "t", name: "test", polyline: TestRoute.line, maneuvers: [turn, arrive],
                            distanceMeters: 2000, durationSeconds: 120, source: "test")
    }

    static var school: RoadFeature {
        RoadFeature(id: "school", kind: .schoolZone, coordinate: TestRoute.point(metersEast: 1500, metersNorth: 100),
                    name: "Carmel Elementary", lanes: nil, legs: nil, maxspeedMph: nil, osmIds: [])
    }

    static var cues: [Cue] { CueListBuilder.build(route: route, cache: cache, features: [school]) }

    @Test func signalsAreMatchedAndDeduplicated() {
        let signals = Self.cues.filter { $0.kind == .signal }
        #expect(signals.count == 2)
        #expect(abs(signals[0].targetMeters - 400) < 3 && abs(signals[1].targetMeters - 800) < 3)
        #expect(signals.allSatisfy { $0.maneuverId == 1 })   // both count toward the right turn
    }

    @Test func turnGetsALaneCueFromTheApproachTag() {
        let lane = Self.cues.first { $0.kind == .laneChange }
        #expect(lane != nil)
        #expect(lane?.targetMeters == 1000)
        #expect(lane?.roadSpeedMph == 45)
        #expect(lane?.laneStrip?.laneCount == 3)
        #expect(lane?.laneStrip?.labels == ["←", "↑", "↑→"])
        let turn = Self.cues.first { $0.kind == .turn }
        #expect(turn?.spokenTemplate == "Turn right onto Main St")
    }

    @Test func speedChangeSchoolStopAndArriveArePlaced() {
        let c = Self.cues
        let speed = c.first { $0.kind == .speedChange }
        #expect(speed != nil && abs(speed!.targetMeters - 1000) < 60)
        #expect(speed?.spokenTemplate.contains("drops to 30") == true)
        let school = c.first { $0.kind == .schoolZone }
        #expect(school != nil && school!.targetMeters > 1350 && school!.targetMeters < 1450)
        #expect(c.contains { $0.kind == .stopSign && abs($0.targetMeters - 1600) < 3 })
        #expect(c.last?.kind == .arrive && c.last?.targetMeters == 2000)
    }

    @Test func placeholdersFill() {
        let lane = Self.cues.first { $0.kind == .laneChange }!
        #expect(lane.spoken(lights: 2) == "Move to the right lane now for your turn, your turn is in 2 lights")
        #expect(lane.spoken(lights: nil) == "Move to the right lane now for your turn")
        let signal = Self.cues.first { $0.kind == .signal }!
        #expect(signal.spoken(lights: 1) == "1 light to go")
        #expect(signal.spoken(lights: 0) == "Your turn is at this light")
    }
}
