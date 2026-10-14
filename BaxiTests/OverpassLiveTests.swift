import Foundation
import Testing
@testable import Baxi

/// Live network check of the Overpass corridor fetch. Skipped unless BAXI_LIVE=1, so `swift test` stays offline.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BAXI_LIVE"] != nil, "set BAXI_LIVE=1 to hit Overpass"))
struct OverpassLiveTests {
    @Test func routeOptionsMeasureFastRoads() async throws {
        let opts = try await RouteService.options(from: Coordinate(lat: 39.9765, lon: -86.1281),
                                                  to: Coordinate(lat: 39.9077, lon: -86.1080), name: "Fashion Mall")
        for o in opts {
            print("LIVE option: \(Int(o.route.durationSeconds / 60)) min, \(String(format: "%.1f", o.route.distanceMeters / 1609.34)) mi,",
                  "\(o.fastMeters.map { String(format: "%.1f", $0 / 1609.34) } ?? "?") mi at 45+")
        }
        if let c = RouteService.calmer(in: opts) { print("LIVE calmer: \(Int(c.route.durationSeconds / 60)) min") } else { print("LIVE no calmer option") }
        #expect(!opts.isEmpty && opts[0].fastMeters != nil)
    }

    @Test func carmelWeatherFromTheNationalWeatherService() async throws {
        let w = try await WeatherService.weather(at: Coordinate(lat: 39.9765, lon: -86.1281))
        print("LIVE weather: \(w.summary), \(w.condition), alerts \(w.alerts), spoken: \(w.spoken ?? "nothing")")
        #expect(!w.summary.isEmpty)
    }

    @Test func westfieldRouteGetsRoadData() async throws {
        // Grand Park, Westfield to Westfield High School: outside the bundled Carmel box.
        let route = try await RouteService.route(from: Coordinate(lat: 40.0533, lon: -86.1631),
                                                 to: Coordinate(lat: 40.0386, lon: -86.1453), name: "Westfield test")
        let start = Date()
        let corridor = try await OverpassService.corridor(along: route.polyline)
        let features = FeatureExtractor.extract(from: corridor)
        let cues = CueListBuilder.build(route: route, cache: corridor, features: features)
        print("LIVE \(String(format: "%.1f", route.distanceMeters / 1609.34)) mi, \(corridor.ways.count) ways, \(corridor.nodes.count) nodes,",
              "\(features.filter { $0.kind.rawValue.contains("oundabout") }.count) roundabouts, \(cues.count) cues in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        for c in cues.prefix(25) { print("LIVE   \(Int(c.targetMeters)) \(c.kind) \(c.spokenTemplate)") }
        #expect(corridor.ways.count > 10)
        #expect(cues.contains { $0.kind == .roundabout || $0.kind == .turn })
    }
}

/// Offline: Overpass JSON into the cache shape, including a way whose geometry has a null point.
struct OverpassParseTests {
    @Test func parsesWaysNodesAndDropsNullGeometryPoints() throws {
        let json = #"""
        {"elements": [
          {"type": "way", "id": 1, "tags": {"highway": "primary", "turn:lanes": "left|through", "surface": "asphalt"},
           "nodes": [10, 11, 12], "geometry": [{"lat": 40.0, "lon": -86.1}, null, {"lat": 40.001, "lon": -86.1}]},
          {"type": "node", "id": 20, "lat": 40.0005, "lon": -86.1, "tags": {"highway": "traffic_signals"}},
          {"type": "way", "id": 2, "tags": {"amenity": "school", "name": "Westfield High"}, "center": {"lat": 40.01, "lon": -86.12}}
        ]}
        """#
        let c = try OverpassService.parse(Data(json.utf8))
        let w = try #require(c.ways.first { $0.id == 1 })
        #expect(w.nodes == [10, 12] && w.geometry?.count == 2)          // node and point kept aligned
        #expect(w.tags["surface"] == nil && w.turnLanes == "left|through")
        #expect(c.nodes.first?.tags["highway"] == "traffic_signals")
        #expect(c.ways.first { $0.id == 2 }?.lat == 40.01)
    }

    @Test func longRoutesAreSplitIntoOverlappingPieces() {
        let line = Polyline((0...200).map { TestRoute.point(metersEast: Double($0) * 100) })   // 20 km
        let pieces = OverpassService.pieces(of: line)
        #expect(pieces.count > 1 && pieces.allSatisfy { $0.count <= OverpassService.pointsPerQuery })
        for (a, b) in zip(pieces, pieces.dropFirst()) { #expect(a.last == b.first) }
        // The ends stay private: nothing sent within 200 m of the start or the end.
        let sent = pieces.flatMap { $0 }
        #expect(sent.allSatisfy { Geo.distanceMeters($0, line.points.first!) >= 199 && Geo.distanceMeters($0, line.points.last!) >= 199 })
    }
}

struct WeatherParseTests {
    @Test func conditionsFromForecastWordsAndAlerts() {
        #expect(RoadWeather.condition(forecast: "Chance Light Rain", alerts: []) == .rain)
        #expect(RoadWeather.condition(forecast: "Freezing Drizzle", alerts: []) == .snowOrIce)
        #expect(RoadWeather.condition(forecast: "Patchy Fog", alerts: []) == .fog)
        #expect(RoadWeather.condition(forecast: "Sunny", alerts: ["Winter Weather Advisory"]) == .snowOrIce)
        #expect(RoadWeather.condition(forecast: "Mostly Sunny", alerts: []) == .clear)
        #expect(RoadWeather(summary: "Sunny, 60°F", condition: .clear, alerts: []).spoken == nil)
        #expect(RoadWeather(summary: "", condition: .rain, alerts: ["Flood Advisory"]).spoken == "Flood Advisory in effect. Rain right now. Roads may be slippery.")
    }

    @Test func alertsSortMostSevereFirst() throws {
        let json = #"""
        {"features": [{"properties": {"event": "Wind Advisory", "severity": "Minor"}},
                      {"properties": {"event": "Winter Storm Warning", "severity": "Severe"}},
                      {"properties": {"event": "Wind Advisory", "severity": "Minor"}}]}
        """#
        #expect(try WeatherService.alertNames(Data(json.utf8)) == ["Winter Storm Warning", "Wind Advisory"])
    }
}

struct CalmerRouteTests {
    func option(_ minutes: Double, fastMiles: Double?) -> RouteService.Option {
        RouteService.Option(route: PlannedRoute(id: UUID().uuidString, name: "r", polyline: TestRoute.line, maneuvers: [],
                                                distanceMeters: 2000, durationSeconds: minutes * 60, source: "osrm"),
                            fastMeters: fastMiles.map { $0 * 1609.34 })
    }

    @Test func calmerMustBeMeaningfullyCalmerAndNotMuchSlower() {
        let fastest = option(14, fastMiles: 3.6)
        #expect(RouteService.calmer(in: [fastest, option(14, fastMiles: 3.1)]) == nil)          // 0.5 mi: not enough
        let calm = option(17, fastMiles: 0.4)
        #expect(RouteService.calmer(in: [fastest, calm])?.id == calm.id)                        // 3 min longer, 3.2 mi less
        #expect(RouteService.calmer(in: [fastest, option(25, fastMiles: 0)]) == nil)             // 79% slower
        #expect(RouteService.calmer(in: [option(14, fastMiles: nil), calm]) == nil)              // fastest unmeasured
    }
}
