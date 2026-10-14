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
        Preset(id: "preset_roundabouts", name: "Roundabout loop", summary: "20 roundabouts around Carmel, single and two-lane, Hazel Dell and 116th"),
        Preset(id: "preset_parkway", name: "Parkway loop", summary: "Keystone Parkway at 50 mph, a fork, a merge and an exit ramp"),
        Preset(id: "preset_highway", name: "Highway ramp loop", summary: "Merge onto US 31, exit through a roundabout interchange, merge again"),
    ]

    static func preset(_ id: String) throws -> PlannedRoute {
        guard let url = Bundle.main.url(forResource: id, withExtension: "json") else { throw BundledData.LoadError.missing(id) }
        return try OSRMParser.parse(Data(contentsOf: url), source: "preset")
    }

    static let osrmBase = "https://router.project-osrm.org/route/v1/driving/"

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
            guard !text.isEmpty else { continue }
            let lower = text.lowercased()
            let kind: Maneuver.Kind = i == r.steps.count - 1 ? .arrive
                : lower.contains("roundabout") ? .roundabout
                : lower.contains("exit") ? .offRamp
                : lower.contains("merge") || lower.contains("ramp") ? .merge
                : lower.contains("left") || lower.contains("right") ? .turn : .continueStraight
            let dir: Maneuver.Direction? = lower.contains("left") ? .left : lower.contains("right") ? .right : nil
            let first = step.polyline.points()[0].coordinate
            maneuvers.append(Maneuver(id: maneuvers.count, kind: kind, direction: dir, location: Coordinate(first),
                                      alongMeters: min(along, line.lengthMeters), exitNumber: nil, roadName: nil,
                                      instruction: text, laneCount: nil, validLanes: nil))
        }
        return PlannedRoute(id: UUID().uuidString, name: name, polyline: line, maneuvers: maneuvers,
                            distanceMeters: line.lengthMeters, durationSeconds: r.expectedTravelTime, source: "apple")
    }
}
