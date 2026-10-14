import Testing
import Foundation
@testable import Baxi

struct OSRMParserTests {
    /// A two-leg OSRM response trimmed by hand: depart, a roundabout with its exit step, a turn with lanes,
    /// a via waypoint (arrive + depart mid-route), and the final arrive.
    static let json = """
    {"code":"Ok","routes":[{"distance":1000,"duration":90,
     "geometry":{"type":"LineString","coordinates":[[-86.15,39.95],[-86.1441,39.95],[-86.1383,39.95]]},
     "legs":[
      {"steps":[
        {"distance":200,"name":"Main St","maneuver":{"type":"depart","location":[-86.15,39.95]},"intersections":[]},
        {"distance":50,"name":"","maneuver":{"type":"roundabout","modifier":"straight","exit":2,"location":[-86.14766,39.95]},"intersections":[]},
        {"distance":250,"name":"Main St","maneuver":{"type":"exit roundabout","location":[-86.1471,39.95]},"intersections":[]},
        {"distance":0,"name":"Main St","maneuver":{"type":"arrive","location":[-86.1441,39.95]},"intersections":[]}]},
      {"steps":[
        {"distance":200,"name":"Main St","maneuver":{"type":"depart","location":[-86.1441,39.95]},"intersections":[]},
        {"distance":300,"name":"E 116th St","maneuver":{"type":"turn","modifier":"right","location":[-86.14176,39.95]},
         "intersections":[{"lanes":[{"valid":false,"indications":["left"]},{"valid":false,"indications":["straight"]},{"valid":true,"indications":["right"]}]}]},
        {"distance":0,"name":"","maneuver":{"type":"arrive","location":[-86.1383,39.95]},"intersections":[]}]}
     ]}]}
    """

    @Test func parsesManeuversAndSkipsNoise() throws {
        let r = try OSRMParser.parse(Data(Self.json.utf8), id: "t", name: "Test")
        #expect(r.maneuvers.map(\.kind) == [.depart, .roundabout, .turn, .arrive])
        let rb = r.maneuvers[1]
        #expect(rb.exitNumber == 2)
        #expect(abs(rb.alongMeters - 200) < 5)
        let turn = r.maneuvers[2]
        #expect(turn.direction == .right && turn.roadName == "E 116th St")
        #expect(turn.laneCount == 3 && turn.validLanes == [2])
        #expect(abs(turn.alongMeters - 700) < 10)
        #expect(r.maneuvers.last?.alongMeters == r.polyline.lengthMeters)
        #expect(turn.instruction == "Turn right onto E 116th St")
    }

    @Test func errorsAreReported() {
        #expect(throws: OSRMParser.ParseError.self) {
            try OSRMParser.parse(Data(#"{"code":"NoRoute","message":"Impossible route"}"#.utf8))
        }
    }

    @Test func bundledHighwayPresetHasRampsAndLanes() throws {
        let r = try RouteService.preset("preset_highway")
        #expect(r.polyline.lengthMeters > 10_000)
        #expect(r.maneuvers.contains { $0.kind == .merge })
        #expect(r.maneuvers.contains { $0.kind == .offRamp })
        #expect(r.maneuvers.contains { $0.kind == .roundabout && $0.exitNumber != nil })
        #expect(r.maneuvers.contains { ($0.laneCount ?? 0) > 1 })
        // Maneuvers come out in route order.
        #expect(r.maneuvers.map(\.alongMeters) == r.maneuvers.map(\.alongMeters).sorted())
    }

    @Test func everyPresetBuildsCuesFromTheCarmelCache() throws {
        let cache = try BundledData.carmelCache()
        let features = FeatureExtractor.extract(from: cache)
        for p in RouteService.presets {
            let r = try RouteService.preset(p.id)
            let cues = CueListBuilder.build(route: r, cache: cache, features: features)
            #expect(cues.contains { $0.kind == .roundabout }, "\(p.id) has no roundabout cue")
            #expect(cues.contains { $0.kind == .laneChange }, "\(p.id) has no lane cue")
            #expect(cues.last?.kind == .arrive)
        }
    }
}

struct HardSpotTests {
    @Test func highwayPresetPreviewHasRampsAndARoundaboutInOrder() throws {
        let cache = try BundledData.carmelCache()
        let features = FeatureExtractor.extract(from: cache)
        let r = try RouteService.preset("preset_highway")
        let cues = CueListBuilder.build(route: r, cache: cache, features: features)
        let spots = HardSpots.find(route: r, cues: cues, features: features)
        #expect(spots.contains { $0.kind == .ramp })
        #expect(spots.contains { $0.kind == .roundabout && $0.title.contains("exit") })
        #expect(spots.map(\.alongMeters) == spots.map(\.alongMeters).sorted())
        #expect(spots.allSatisfy { !$0.spoken.isEmpty && !$0.spoken.contains("{") })
        #expect(Set(spots.map(\.id)).count == spots.count)
    }
}
