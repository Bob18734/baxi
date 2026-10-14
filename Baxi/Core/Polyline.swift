import Foundation

/// A route line with cumulative distances, so anything on the route can be placed by
/// "meters from the start". Every cue and every location fix is expressed this way.
struct Polyline: Equatable {
    let points: [Coordinate]
    /// cumulative[i] = meters from points[0] to points[i].
    let cumulative: [Double]

    init(_ points: [Coordinate]) {
        self.points = points
        var acc = 0.0
        var cum: [Double] = []
        cum.reserveCapacity(points.count)
        for (i, p) in points.enumerated() {
            if i > 0 { acc += Geo.distanceMeters(points[i - 1], p) }
            cum.append(acc)
        }
        cumulative = cum
    }

    var lengthMeters: Double { cumulative.last ?? 0 }
    var segmentCount: Int { max(0, points.count - 1) }

    struct Projection: Equatable {
        let segmentIndex: Int
        /// 0 at the segment start, 1 at its end.
        let t: Double
        let point: Coordinate
        let crossTrackMeters: Double
        let alongMeters: Double
    }

    /// Nearest point on the line. With `near`, only segments from near-back to near+window are searched,
    /// which is what route following does once it knows roughly where the car is.
    func project(_ p: Coordinate, near: Int? = nil, back: Int = 3, window: Int = 40) -> Projection? {
        guard segmentCount > 0 else { return nil }
        let lo = near.map { max(0, $0 - back) } ?? 0
        let hi = near.map { min(segmentCount - 1, $0 + window) } ?? (segmentCount - 1)
        var best: Projection?
        for i in lo...hi {
            let r = Geo.projectOntoSegment(p, points[i], points[i + 1])
            if best == nil || r.distanceMeters < best!.crossTrackMeters {
                let segLen = cumulative[i + 1] - cumulative[i]
                best = Projection(segmentIndex: i, t: r.t, point: r.point, crossTrackMeters: r.distanceMeters,
                                  alongMeters: cumulative[i] + r.t * segLen)
            }
        }
        return best
    }

    /// The point `meters` from the start, clamped to the line.
    func coordinate(atMeters meters: Double) -> Coordinate? {
        guard let first = points.first else { return nil }
        if meters <= 0 { return first }
        if meters >= lengthMeters { return points.last }
        // Binary search the segment.
        var lo = 0, hi = cumulative.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= meters { lo = mid } else { hi = mid }
        }
        let segLen = cumulative[hi] - cumulative[lo]
        let f = segLen == 0 ? 0 : (meters - cumulative[lo]) / segLen
        return Geo.interpolate(points[lo], points[hi], fraction: f)
    }

    /// Compass bearing of travel at `meters` along the line.
    func bearing(atMeters meters: Double) -> Double? {
        guard segmentCount > 0 else { return nil }
        var i = 0
        while i < segmentCount - 1 && cumulative[i + 1] <= meters { i += 1 }
        return Geo.bearingDegrees(from: points[i], to: points[i + 1])
    }

    /// Sample points every `stepMeters`, each with its along-route distance. Used to match
    /// road data (speed limits, crash corridors) to the route.
    func samples(everyMeters stepMeters: Double) -> [(alongMeters: Double, point: Coordinate)] {
        guard lengthMeters > 0 else { return points.first.map { [(0, $0)] } ?? [] }
        var out: [(Double, Coordinate)] = []
        var m = 0.0
        while m <= lengthMeters {
            if let c = coordinate(atMeters: m) { out.append((m, c)) }
            m += stepMeters
        }
        if let last = points.last, (out.last?.0 ?? -1) < lengthMeters { out.append((lengthMeters, last)) }
        return out
    }
}
