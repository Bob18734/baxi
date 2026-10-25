import Foundation
import MapKit

/// Gets a route: the bundled presets, OSRM for anything else, Apple directions if OSRM fails.
enum RouteService {
    struct Preset: Identifiable, Hashable {
        let id: String
        let name: String
        let summary: String
    }

    static let presets: [Preset] = [
        Preset(id: "preset_roundabouts", name: "Roundabout loop", summary: "16 roundabouts, single and two-lane, on 116th Street, River Road and 126th Street"),
        Preset(id: "preset_parkway", name: "Parkway loop", summary: "Keystone Parkway at 50 mph, a fork, a merge and an exit ramp"),
        Preset(id: "preset_highway", name: "Highway ramp loop", summary: "Merge onto US 31, exit through a roundabout interchange, merge again"),
    ]

    static func preset(_ id: String) throws -> PlannedRoute {
        guard let url = Bundle.baxi.url(forResource: id, withExtension: "json") else { throw BundledData.LoadError.missing(id) }
        return try OSRMParser.parse(Data(contentsOf: url), source: "preset")
    }

    /// Carmel City Center, where the presets start; also where a searched route starts when the phone's
    /// location is unknown (denied, no fix yet).
    static let carmelCityCenter = Coordinate(lat: 39.9765, lon: -86.1281)

    /// Where a searched route starts: the phone's own position when known, else Carmel City Center.
    static func origin(fix: Coordinate?) -> Coordinate { fix ?? carmelCityCenter }

    static let osrmBase = "https://router.project-osrm.org/route/v1/driving/"

    /// A route to choose, with how much of it is on fast, busy roads (nil when the router did not say).
    struct Option: Identifiable {
        let route: PlannedRoute
        let fastMeters: Double?
        var id: String { route.id }
    }

    /// The fastest route plus OSRM's alternatives, for offering a calmer one; Apple directions alone if
    /// OSRM fails.
    static func options(from a: Coordinate, to b: Coordinate, name: String) async throws -> [Option] {
        do {
            let coords = "\(a.lon),\(a.lat);\(b.lon),\(b.lat)"
            var req = URLRequest(url: URL(string: osrmBase + coords
                + "?overview=full&geometries=geojson&steps=true&alternatives=2&annotations=speed,distance")!)
            req.timeoutInterval = 15
            req.setValue("baxi-cac-2026/0.1", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            let all = try OSRMParser.parseAll(data, name: name)
            guard !all.isEmpty else { throw OSRMParser.ParseError.noRoute }
            return all.map { Option(route: $0.route, fastMeters: $0.fastMeters) }
        } catch {
            return [Option(route: try await apple(from: a, to: b, name: name), fastMeters: nil)]
        }
    }

    /// The option to offer as calmer: at least a mile less on fast roads than the fastest, and no more
    /// than 30% slower. nil when no alternative is meaningfully calmer.
    static func calmer(in options: [Option]) -> Option? {
        guard let fastest = options.first, let fastestFast = fastest.fastMeters else { return nil }
        return options.dropFirst()
            .filter { o in
                guard let f = o.fastMeters else { return false }
                return f <= fastestFast - 1_609 && o.route.durationSeconds <= fastest.route.durationSeconds * 1.3
            }
            .min { ($0.fastMeters ?? 0) < ($1.fastMeters ?? 0) }
    }

    static func route(from a: Coordinate, to b: Coordinate, name: String) async throws -> PlannedRoute {
        do {
            return try await osrm(from: a, to: b, name: name)
        } catch {
            return try await apple(from: a, to: b, name: name)
        }
    }

    static func osrm(from a: Coordinate, to b: Coordinate, name: String) async throws -> PlannedRoute {
        let coords = "\(a.lon),\(a.lat);\(b.lon),\(b.lat)"
        var req = URLRequest(url: URL(string: osrmBase + coords + "?overview=full&geometries=geojson&steps=true")!)
        req.timeoutInterval = 15
        req.setValue("baxi-cac-2026/0.1", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try OSRMParser.parse(data, id: UUID().uuidString, name: name)
    }

    /// Apple directions: no exit numbers and no lane data, so roundabouts and lane cues are weaker.
    static func apple(from a: Coordinate, to b: Coordinate, name: String) async throws -> PlannedRoute {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: a.clLocation))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: b.clLocation))
        req.transportType = .automobile
        let resp = try await MKDirections(request: req).calculate()
        guard let r = resp.routes.first else { throw OSRMParser.ParseError.noRoute }
        let pts = r.polyline.points()
        let line = Polyline((0..<r.polyline.pointCount).map { Coordinate(pts[$0].coordinate) })
        var along = 0.0
        var maneuvers: [Maneuver] = []
        for (i, step) in r.steps.enumerated() {
            // An Apple step's instruction applies where the step starts.
            defer { along += step.distance }
            let text = step.instructions
            guard !text.isEmpty, step.polyline.pointCount > 0 else { continue }
            let read = appleStep(text, isLast: i == r.steps.count - 1)
            let first = step.polyline.points()[0].coordinate
            maneuvers.append(Maneuver(id: maneuvers.count, kind: read.kind, direction: read.direction, location: Coordinate(first),
                                      alongMeters: min(along, line.lengthMeters), exitNumber: read.exitNumber, roadName: nil,
                                      instruction: text, laneCount: nil, validLanes: nil))
        }
        return PlannedRoute(id: UUID().uuidString, name: name, polyline: line, maneuvers: maneuvers,
                            distanceMeters: line.lengthMeters, durationSeconds: r.expectedTravelTime, source: "apple")
    }

    /// Reads one Apple step instruction ("At the roundabout, take the 3rd exit onto Main St",
    /// "Make a U-turn", "Keep left at the fork") into a maneuver. Apple gives only text, so a roundabout
    /// whose exit cannot be read keeps exitNumber nil, and Baxi then makes no exit or lane claim.
    static func appleStep(_ text: String, isLast: Bool) -> (kind: Maneuver.Kind, direction: Maneuver.Direction?, exitNumber: Int?) {
        let lower = text.lowercased()
        let left = lower.contains("left"), right = lower.contains("right")
        let side: Maneuver.Direction? = left ? .left : right ? .right : nil
        if isLast { return (.arrive, nil, nil) }
        if lower.contains("roundabout") || lower.contains("traffic circle") || lower.contains("rotary") {
            return (.roundabout, side, exitOrdinal(lower))
        }
        if lower.contains("u-turn") || lower.contains("u turn") { return (.turn, .uturn, nil) }
        if lower.hasPrefix("keep") || lower.contains("at the fork") {
            return (.fork, left ? .slightLeft : right ? .slightRight : nil, nil)
        }
        if lower.contains("exit") { return (.offRamp, side ?? .right, nil) }
        if lower.contains("merge") || lower.contains("ramp") { return (.merge, side, nil) }
        if left || right {
            let sharp = lower.contains("sharp"), slight = lower.contains("slight") || lower.contains("bear")
            let d: Maneuver.Direction = left ? (sharp ? .sharpLeft : slight ? .slightLeft : .left)
                                             : (sharp ? .sharpRight : slight ? .slightRight : .right)
            return (.turn, d, nil)
        }
        return (.continueStraight, nil, nil)
    }

    /// "3rd exit", "third exit" -> 3.
    static func exitOrdinal(_ lower: String) -> Int? {
        let words = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8]
        for (w, n) in words where lower.contains("\(w) exit") { return n }
        guard let r = lower.range(of: #"(\d+)(st|nd|rd|th) exit"#, options: .regularExpression) else { return nil }
        return Int(lower[r].prefix { $0.isNumber })
    }
}
