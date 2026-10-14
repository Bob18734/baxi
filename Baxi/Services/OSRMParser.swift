import Foundation

/// Turns an OSRM /route response (overview=full, geometries=geojson, steps=true) into a PlannedRoute.
/// The same parser reads live responses and the preset routes bundled in Resources/Routes.
enum OSRMParser {
    enum ParseError: Error { case notOk(String), noRoute }

    private struct Response: Decodable {
        let code: String
        let message: String?
        let routes: [Route]?
        let baxi: Meta?
    }
    private struct Meta: Decodable { let id: String; let name: String }
    private struct Route: Decodable {
        let distance: Double
        let duration: Double
        let geometry: Geometry
        let legs: [Leg]
    }
    private struct Geometry: Decodable { let coordinates: [[Double]] }
    private struct Leg: Decodable { let steps: [Step]; let annotation: Annotation? }
    /// Per-segment values when requested with annotations=speed,distance.
    private struct Annotation: Decodable { let speed: [Double]?; let distance: [Double]? }
    private struct Step: Decodable {
        let distance: Double
        let name: String?
        let ref: String?
        let maneuver: StepManeuver
        let intersections: [Intersection]?
    }
    private struct StepManeuver: Decodable {
        let type: String
        let modifier: String?
        let location: [Double]
        let exit: Int?
    }
    private struct Intersection: Decodable {
        let lanes: [Lane]?
    }
    private struct Lane: Decodable { let valid: Bool; let indications: [String] }

    /// Roads posted 45 mph or more: highways and fast arterials, the busy roads. OSRM's car profile
    /// expects about 80% of the posted limit (Keystone Parkway, posted 50, comes back as 18.5 m/s on
    /// Oct 14, 2026), so 45 mph posted is about 16 m/s here.
    static let fastMetersPerSecond = 16.0

    /// Every route in the response (the first is OSRM's fastest; more when asked for alternatives), each
    /// with its meters at 45 mph or more when the response carries speed annotations.
    static func parseAll(_ data: Data, name: String) throws -> [(route: PlannedRoute, fastMeters: Double?)] {
        let r = try JSONDecoder().decode(Response.self, from: data)
        guard r.code == "Ok" else { throw ParseError.notOk(r.message ?? r.code) }
        return try (r.routes ?? []).indices.map { i in
            let route = try parse(data, index: i, id: UUID().uuidString, name: name)
            let fast: Double? = r.routes![i].legs.reduce(Optional(0.0)) { total, leg in
                guard let total, let s = leg.annotation?.speed, let d = leg.annotation?.distance, s.count == d.count else { return nil }
                return total + zip(s, d).filter { $0.0 >= fastMetersPerSecond }.map(\.1).reduce(0, +)
            }
            return (route, fast)
        }
    }

    static func parse(_ data: Data, index: Int = 0, id: String? = nil, name: String? = nil, source: String = "osrm") throws -> PlannedRoute {
        let r = try JSONDecoder().decode(Response.self, from: data)
        guard r.code == "Ok" else { throw ParseError.notOk(r.message ?? r.code) }
        guard let routes = r.routes, index < routes.count else { throw ParseError.noRoute }
        let route = routes[index]

        let line = Polyline(route.geometry.coordinates.compactMap { $0.count >= 2 ? Coordinate(lat: $0[1], lon: $0[0]) : nil })
        // OSRM's step distances and our haversine length differ by a fraction of a percent; scale to match.
        let scale = route.distance > 0 ? line.lengthMeters / route.distance : 1

        var maneuvers: [Maneuver] = []
        var stepStart = 0.0
        let legs = route.legs
        for (li, leg) in legs.enumerated() {
            for (si, step) in leg.steps.enumerated() {
                defer { stepStart += step.distance }
                let isFirstDepart = li == 0 && si == 0
                let isLastArrive = li == legs.count - 1 && si == leg.steps.count - 1
                guard let kind = kind(for: step.maneuver, isFirstDepart: isFirstDepart, isLastArrive: isLastArrive) else { continue }
                let loc = Coordinate(lat: step.maneuver.location[1], lon: step.maneuver.location[0])
                let estimate = stepStart * scale
                let along = isLastArrive ? line.lengthMeters
                    : (line.project(loc, expectedAlong: estimate)?.alongMeters ?? estimate)
                let lanes = step.intersections?.first?.lanes
                let roadName = [step.name, step.ref].compactMap { $0 }.first { !$0.isEmpty }
                maneuvers.append(Maneuver(
                    id: maneuvers.count,
                    kind: kind,
                    direction: direction(step.maneuver.modifier),
                    location: loc,
                    alongMeters: along,
                    exitNumber: kind == .roundabout ? step.maneuver.exit : nil,
                    roadName: roadName,
                    instruction: sentence(kind: kind, modifier: step.maneuver.modifier, exit: step.maneuver.exit, road: roadName),
                    laneCount: lanes.map(\.count),
                    validLanes: lanes.map { ls in ls.indices.filter { ls[$0].valid } }))
            }
        }
        return PlannedRoute(id: id ?? r.baxi?.id ?? UUID().uuidString, name: name ?? r.baxi?.name ?? "Route",
                            polyline: line, maneuvers: maneuvers, distanceMeters: line.lengthMeters,
                            durationSeconds: route.duration, source: source)
    }

    /// OSRM maneuver types to ours. nil means the step is not worth a maneuver of its own
    /// (a roundabout's exit step, a name change, a waypoint's arrive and depart mid-route).
    static func kindFor(type: String, modifier: String?, isFirstDepart: Bool, isLastArrive: Bool) -> Maneuver.Kind? {
        switch type {
        case "depart": return isFirstDepart ? .depart : nil
        case "arrive": return isLastArrive ? .arrive : nil
        case "roundabout", "rotary": return .roundabout
        case "roundabout turn": return modifier == nil || modifier == "straight" ? .continueStraight : .turn
        case "exit roundabout", "exit rotary", "new name", "notification", "use lane": return nil
        case "on ramp": return .onRamp
        case "off ramp": return .offRamp
        case "merge": return .merge
        case "fork": return .fork
        case "turn", "end of road", "continue":
            if modifier == nil || modifier == "straight" { return type == "end of road" ? .turn : .continueStraight }
            return .turn
        default: return .other
        }
    }

    private static func kind(for m: StepManeuver, isFirstDepart: Bool, isLastArrive: Bool) -> Maneuver.Kind? {
        kindFor(type: m.type, modifier: m.modifier, isFirstDepart: isFirstDepart, isLastArrive: isLastArrive)
    }

    static func direction(_ modifier: String?) -> Maneuver.Direction? {
        switch modifier {
        case "left": .left
        case "right": .right
        case "slight left": .slightLeft
        case "slight right": .slightRight
        case "sharp left": .sharpLeft
        case "sharp right": .sharpRight
        case "straight": .straight
        case "uturn": .uturn
        default: nil
        }
    }

    static func sentence(kind: Maneuver.Kind, modifier: String?, exit: Int?, road: String?) -> String {
        let onto = road.map { " onto \($0)" } ?? ""
        switch kind {
        case .depart: return "Head out\(onto)"
        case .arrive: return "Arrive"
        case .roundabout: return "At the roundabout, take exit \(exit ?? 1)\(onto)"
        case .onRamp: return "Take the ramp\(onto)"
        case .offRamp: return "Take the exit\(onto)"
        case .merge: return "Merge\(onto)"
        case .fork: return "Keep \(modifier?.contains("left") == true ? "left" : "right") at the fork\(onto)"
        case .continueStraight: return "Continue straight\(onto)"
        case .turn: return "Turn \(modifier ?? "")\(onto)"
        case .other: return "Continue\(onto)"
        }
    }
}
