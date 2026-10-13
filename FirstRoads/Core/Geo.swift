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
        let kx = cos(a.lat.radians) * earthRadiusMeters * Double.pi / 180
        let ky = earthRadiusMeters * Double.pi / 180
        let ax = 0.0, ay = 0.0
        let bx = (b.lon - a.lon) * kx, by = (b.lat - a.lat) * ky
        let px = (p.lon - a.lon) * kx, py = (p.lat - a.lat) * ky
        let len2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay)
        var t = len2 == 0 ? 0 : ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / len2
        t = max(0, min(1, t))
        let cx = ax + t * (bx - ax), cy = ay + t * (by - ay)
        return sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
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
