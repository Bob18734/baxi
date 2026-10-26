import Foundation

/// Small geometry helpers on plain Coordinates. Pure functions, unit tested.
enum Geo {
    static let earthRadiusMeters = 6_371_000.0

    /// Great-circle distance in meters.
    static func distanceMeters(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = (b.lat - a.lat).radians, dLon = (b.lon - a.lon).radians
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat.radians) * cos(b.lat.radians) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }

    /// Initial compass bearing from a to b, 0 to 360, 0 = north, 90 = east.
    static func bearingDegrees(from a: Coordinate, to b: Coordinate) -> Double {
        let dLon = (b.lon - a.lon).radians
        let y = sin(dLon) * cos(b.lat.radians)
        let x = cos(a.lat.radians) * sin(b.lat.radians) - sin(a.lat.radians) * cos(b.lat.radians) * cos(dLon)
        let deg = atan2(y, x).degrees
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Shortest distance in meters from a point to a polyline, good enough at city scale.
    static func distanceMeters(from p: Coordinate, toPolyline line: [Coordinate]) -> Double {
        guard let first = line.first else { return .infinity }
        guard line.count > 1 else { return distanceMeters(p, first) }
        var best = Double.infinity
        for i in 0..<(line.count - 1) {
            best = min(best, distanceMeters(from: p, toSegment: line[i], line[i + 1]))
        }
        return best
    }

    /// Distance from p to the segment ab using a local flat projection.
    static func distanceMeters(from p: Coordinate, toSegment a: Coordinate, _ b: Coordinate) -> Double {
        projectOntoSegment(p, a, b).distanceMeters
    }

    /// Projects p onto the segment ab. `t` is 0 at a and 1 at b, clamped to the segment.
    static func projectOntoSegment(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate)
        -> (t: Double, distanceMeters: Double, point: Coordinate) {
        let kx = cos(a.lat.radians) * earthRadiusMeters * Double.pi / 180
        let ky = earthRadiusMeters * Double.pi / 180
        let bx = (b.lon - a.lon) * kx, by = (b.lat - a.lat) * ky
        let px = (p.lon - a.lon) * kx, py = (p.lat - a.lat) * ky
        let len2 = bx * bx + by * by
        var t = len2 == 0 ? 0 : (px * bx + py * by) / len2
        t = max(0, min(1, t))
        let cx = t * bx, cy = t * by
        let dist = sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
        let point = Coordinate(lat: a.lat + cy / ky, lon: a.lon + cx / kx)
        return (t, dist, point)
    }

    /// A point `fraction` of the way from a to b (straight interpolation, fine at city scale).
    /// The point `meters` from `c` along a compass bearing (flat-earth, fine for a few hundred meters).
    static func offset(_ c: Coordinate, bearingDegrees: Double, meters: Double) -> Coordinate {
        let rad = bearingDegrees * .pi / 180
        let dLat = meters * cos(rad) / 110_540
        let dLon = meters * sin(rad) / (111_320 * cos(c.lat * .pi / 180))
        return Coordinate(lat: c.lat + dLat, lon: c.lon + dLon)
    }

    static func interpolate(_ a: Coordinate, _ b: Coordinate, fraction: Double) -> Coordinate {
        Coordinate(lat: a.lat + (b.lat - a.lat) * fraction, lon: a.lon + (b.lon - a.lon) * fraction)
    }

    /// Mean of a set of coordinates.
    static func centroid(_ pts: [Coordinate]) -> Coordinate? {
        guard !pts.isEmpty else { return nil }
        return Coordinate(lat: pts.map(\.lat).reduce(0, +) / Double(pts.count),
                          lon: pts.map(\.lon).reduce(0, +) / Double(pts.count))
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}

/// A latitude/longitude box, for skipping far-away geometry before any distance math.
struct GeoBox {
    var minLat = Double.infinity, maxLat = -Double.infinity, minLon = Double.infinity, maxLon = -Double.infinity

    init<S: Sequence>(_ points: S) where S.Element == Coordinate {
        for p in points { minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat); minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon) }
    }

    /// Grown by `meters` on every side.
    func expanded(by meters: Double) -> GeoBox {
        var b = self
        let dLat = meters / 111_195, dLon = meters / (111_195 * max(0.2, cos(((minLat + maxLat) / 2) * .pi / 180)))
        b.minLat -= dLat; b.maxLat += dLat; b.minLon -= dLon; b.maxLon += dLon
        return b
    }

    func contains(_ p: Coordinate) -> Bool { p.lat >= minLat && p.lat <= maxLat && p.lon >= minLon && p.lon <= maxLon }
    func intersects(_ o: GeoBox) -> Bool { minLat <= o.maxLat && maxLat >= o.minLat && minLon <= o.maxLon && maxLon >= o.minLon }
}

