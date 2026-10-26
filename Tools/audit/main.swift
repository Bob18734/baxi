// Checks every demo route's maneuvers against the road geometry, independently of the cue logic:
// the turn angle the route line actually makes, the roundabout exit counted on the OpenStreetMap ring,
// and the lane tags on the approach. Prints one table per route; "CHECK" rows need a human look.
//
//   swift run baxi-audit                 all presets
//   swift run baxi-audit preset_highway  one
@testable import Baxi
import Foundation

let cache = try BundledData.carmelCache()
let features = FeatureExtractor.extract(from: cache)
let hin = try? BundledData.highInjuryNetwork()
let ids = CommandLine.arguments.dropFirst().first.map { [$0] } ?? RouteService.presets.map(\.id)

func norm180(_ d: Double) -> Double { var x = d.truncatingRemainder(dividingBy: 360); if x > 180 { x -= 360 }; if x <= -180 { x += 360 }; return x }

/// The turn the line makes at `along`: bearing over the 30 m after minus the 30 m before. + is right.
func turnAngle(_ line: Polyline, at along: Double, span: Double = 30) -> Double? {
    guard let a = line.coordinate(atMeters: max(0, along - span)), let b = line.coordinate(atMeters: along),
          let c = line.coordinate(atMeters: min(line.lengthMeters, along + span)) else { return nil }
    guard Geo.distanceMeters(a, b) > 3, Geo.distanceMeters(b, c) > 3 else { return nil }
    return norm180(Geo.bearingDegrees(from: b, to: c) - Geo.bearingDegrees(from: a, to: b))
}

func expected(_ angle: Double) -> Set<Maneuver.Direction> {
    let a = abs(angle), right = angle > 0
    switch a {
    case ..<12: return [.straight, .slightLeft, .slightRight]
    case ..<35: return right ? [.slightRight, .straight, .right] : [.slightLeft, .straight, .left]
    case ..<60: return right ? [.slightRight, .right] : [.slightLeft, .left]
    case ..<125: return right ? [.right] : [.left]
    case ..<160: return right ? [.right, .sharpRight] : [.left, .sharpLeft]
    default: return [.uturn, .sharpLeft, .sharpRight]
    }
}

// Ring ways and who touches each node.
let ringWays = cache.ways.filter(\.isRoundabout)
var touching: [Int: [OSMWay]] = [:]
let drivable: Set<String> = ["motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential",
                             "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link", "service", "living_street"]
for w in cache.ways where !w.isRoundabout && drivable.contains(w.highway ?? "") {
    for n in w.nodes ?? [] { touching[n, default: []].append(w) }
}
var nodeCoord: [Int: Coordinate] = [:]
for w in cache.ways { for (n, g) in zip(w.nodes ?? [], w.geometry ?? []) where g.count == 2 { nodeCoord[n] = Coordinate(lat: g[0], lon: g[1]) } }

/// The ring's nodes in driving order (OSM draws roundabouts in the direction of travel), joined across ways.
func ring(near p: Coordinate) -> [Int]? {
    guard let first = ringWays.min(by: { Geo.distanceMeters(from: p, toPolyline: $0.coordinates) < Geo.distanceMeters(from: p, toPolyline: $1.coordinates) }),
          Geo.distanceMeters(from: p, toPolyline: first.coordinates) < 60 else { return nil }
    var order = first.nodes ?? []
    var used: Set<Int> = [first.id]
    while let last = order.last, order.first != last,
          let next = ringWays.first(where: { !used.contains($0.id) && $0.nodes?.first == last }) {
        used.insert(next.id); order += (next.nodes ?? []).dropFirst()
    }
    if order.first == order.last { order.removeLast() }
    return order
}

/// Ways leaving the ring at `node` that a car can take out (not one-way into the ring).
func exits(at node: Int) -> [OSMWay] {
    (touching[node] ?? []).filter { w in
        guard let ns = w.nodes, let i = ns.firstIndex(of: node) else { return false }
        let oneway = w.tags["oneway"] == "yes" || w.highway == "motorway_link"
        if !oneway { return true }
        return i < ns.count - 1     // one-way drawn away from the ring
    }
}

for id in ids {
    let route = try RouteService.preset(id)
    let line = route.polyline
    let prep = RoutePrep.make(route: route, cache: cache, features: features, highInjury: hin)
    let cues = prep.planned(for: .gettingComfortable, route: route)
    print("\n== \(id): \(route.maneuvers.count) maneuvers, \(Int(line.lengthMeters)) m, polyline ends \(route.maneuvers.last.map { Int($0.alongMeters) } ?? -1)")
    for m in route.maneuvers {
        let cue = cues.first { $0.maneuverId == m.id && $0.kind != .laneChange && $0.kind != .signal }
        let said = cue.map { $0.spokenTemplate.replacingOccurrences(of: "{in}", with: "").replacingOccurrences(of: "{reminder}", with: "") } ?? "(nothing)"
        var verdict = "ok", detail = ""
        switch m.kind {
        case .turn, .fork, .offRamp, .continueStraight:
            if let a = turnAngle(line, at: m.alongMeters) {
                detail = String(format: "angle %+.0f°", a)
                if let d = m.direction, !expected(a).contains(d) { verdict = "CHECK" }
            } else { verdict = "CHECK"; detail = "no geometry" }
        case .roundabout:
            guard let r = ring(near: m.location), let exitN = m.exitNumber else { verdict = "CHECK"; detail = "no OSM ring"; break }
            // Entry: ring node nearest the line just before the maneuver; leave: first line point 30 m+ off the ring.
            let ringPts = r.compactMap { nodeCoord[$0] }
            func nearestNode(_ p: Coordinate) -> Int? { r.indices.min { Geo.distanceMeters(nodeCoord[r[$0]] ?? p, p) < Geo.distanceMeters(nodeCoord[r[$1]] ?? p, p) } }
            var leaveAlong = m.alongMeters + 5, leaveIdx: Int?
            var lastOn = m.alongMeters
            while leaveAlong < m.alongMeters + 500, let p = line.coordinate(atMeters: leaveAlong) {
                if Geo.distanceMeters(from: p, toPolyline: ringPts + [ringPts[0]]) < 6 { lastOn = leaveAlong }
                else if leaveAlong - lastOn > 25 { break }
                leaveAlong += 3
            }
            guard let entryP = line.coordinate(atMeters: m.alongMeters), let leaveP = line.coordinate(atMeters: lastOn),
                  let ei = nearestNode(entryP), let li = nearestNode(leaveP) else { verdict = "CHECK"; detail = "can't place"; break }
            leaveIdx = li
            var all = 0, roads = 0, i = (ei + 1) % r.count, names: [String] = []
            while true {
                let ex = exits(at: r[i])
                if !ex.isEmpty {
                    all += 1
                    if ex.contains(where: { $0.highway != "service" }) { roads += 1 }
                    names.append((ex.first { $0.highway != "service" } ?? ex[0]).name ?? (ex[0].highway == "service" ? "driveway" : "unnamed"))
                }
                if i == leaveIdx { break }
                i = (i + 1) % r.count
                if i == (ei + 1) % r.count { break }
            }
            let angle = turnAngle(line, at: (m.alongMeters + lastOn) / 2, span: max(40, (lastOn - m.alongMeters) / 2 + 30))
            let circle = features.filter { [.singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout].contains($0.kind) }
                .min { Geo.distanceMeters($0.coordinate, m.location) < Geo.distanceMeters($1.coordinate, m.location) }
                .flatMap { Geo.distanceMeters($0.coordinate, m.location) <= 80 ? $0.coordinate : nil }
            let shape = RoundaboutDiagram.shape(for: m, route: route, center: circle)
            detail = (shape.map { String(format: "sign angle %.0f° (%@), ", $0.exitAngle, "\(LanePicker.side(exitAngle: $0.exitAngle, exitNumber: exitN))") } ?? "no sign shape, ")
            detail += "router exit \(exitN), ring exits \(all) (roads \(roads)) [\(names.joined(separator: ", "))]" + (angle.map { String(format: ", net turn %+.0f°", $0) } ?? "")
            if all != exitN && roads != exitN { verdict = "CHECK" }
            else if all != roads { verdict = "NOTE"; detail += " — a driveway is counted or not" }
        default: break
        }
        let lane = cue?.laneStrip.map { s in " lanes " + s.labels.enumerated().map { s.highlighted.contains($0.offset) ? "[\($0.element.isEmpty ? "?" : $0.element)]" : ($0.element.isEmpty ? "·" : $0.element) }.joined(separator: " ") } ?? ""
        print(String(format: "%@ %6.0f m  %-10@ %-11@ %@ | %@%@", verdict.padding(toLength: 5, withPad: " ", startingAt: 0), m.alongMeters,
                     m.kind.rawValue as NSString, (m.direction?.rawValue ?? "-") as NSString, detail, said, lane))
    }
}
