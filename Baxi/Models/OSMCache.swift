import Foundation

/// Raw OpenStreetMap elements as written by scripts/build_carmel_cache.py.
/// The app keeps these raw so the extractor and the student modules work on real tags.
struct OSMCache: Codable {
    let source: String
    let bbox: String
    let fetched: String
    let ways: [OSMWay]
    let nodes: [OSMNode]
}

struct OSMWay: Codable, Identifiable, Hashable {
    let id: Int
    let tags: [String: String]
    /// Node ids in order along the way. Two ways touch when they share a node id.
    let nodes: [Int]?
    /// [lat, lon] pairs in order along the way.
    let geometry: [[Double]]?
    /// Center point when the way was fetched without geometry (schools).
    let lat: Double?
    let lon: Double?

    var isRoundabout: Bool { tags["junction"] == "roundabout" }
    var highway: String? { tags["highway"] }
    var name: String? { tags["name"] }
    var lanes: Int? { tags["lanes"].flatMap { Int($0) } }
    var turnLanes: String? { tags["turn:lanes"] }

    /// turn:lanes for a car travelling on bearing `heading` near `point`: `turn:lanes:forward` when that
    /// matches the way's drawn direction, `turn:lanes:backward` when against it, else plain `turn:lanes`.
    func turnLanes(travelling heading: Double, near point: Coordinate) -> String? {
        let fwd = tags["turn:lanes:forward"], back = tags["turn:lanes:backward"]
        guard fwd != nil || back != nil else { return turnLanes }
        let pts = coordinates
        guard pts.count >= 2 else { return turnLanes }
        let i = (0..<(pts.count - 1)).min {
            Geo.distanceMeters(from: point, toPolyline: [pts[$0], pts[$0 + 1]]) < Geo.distanceMeters(from: point, toPolyline: [pts[$1], pts[$1 + 1]])
        }!
        let diff = abs(((Geo.bearingDegrees(from: pts[i], to: pts[i + 1]) - heading) + 540).truncatingRemainder(dividingBy: 360) - 180)
        return (diff < 90 ? fwd : back) ?? turnLanes
    }

    /// Posted limit in mph, parsed from "45 mph" or "45".
    var maxspeedMph: Int? {
        guard let raw = tags["maxspeed"] else { return nil }
        let digits = raw.split(separator: " ").first.map(String.init) ?? raw
        return Int(digits)
    }

    var coordinates: [Coordinate] {
        (geometry ?? []).compactMap { pair in
            pair.count == 2 ? Coordinate(lat: pair[0], lon: pair[1]) : nil
        }
    }

    var center: Coordinate? {
        if let lat, let lon { return Coordinate(lat: lat, lon: lon) }
        let pts = coordinates
        guard !pts.isEmpty else { return nil }
        return Coordinate(lat: pts.map(\.lat).reduce(0, +) / Double(pts.count),
                          lon: pts.map(\.lon).reduce(0, +) / Double(pts.count))
    }
}

struct OSMNode: Codable, Identifiable, Hashable {
    let id: Int
    let tags: [String: String]
    let lat: Double
    let lon: Double
    var coordinate: Coordinate { Coordinate(lat: lat, lon: lon) }
}
