import Foundation

// Written by Claude (Oct 14) at the team's request; originally set aside for the partner. See AI_DISCLOSURE.md.
// Tests: BaxiTests/ApproachHeadingTests.swift.

enum ApproachHeading {
    static let isImplemented = true

    /// The compass bearing a driver faces when arriving at `spot` along `route`.
    /// Used to aim the map on each Preview card so it shows the spot the way the driver will see it.
    /// (Apple's public API cannot aim the Look Around image itself.)
    /// Rules the tests check:
    /// 1. Find the route point nearest the spot (call its index i).
    /// 2. Walk backwards from i until the walked distance is at least `lookBackMeters` (default 40) or the route starts; call that index j.
    /// 3. Return Geo.bearingDegrees(from: route[j], to: route[i]).
    /// 4. Fewer than two route points, or i == j (the spot is at the route start): return nil.
    static func bearing(route: [Coordinate], spot: Coordinate, lookBackMeters: Double = 40) -> Double? {
        guard route.count >= 2,
              let i = route.indices.min(by: { Geo.distanceMeters(route[$0], spot) < Geo.distanceMeters(route[$1], spot) })
        else { return nil }
        var j = i
        var walked = 0.0
        while j > 0 && walked < lookBackMeters {
            walked += Geo.distanceMeters(route[j - 1], route[j])
            j -= 1
        }
        guard j != i else { return nil }
        return Geo.bearingDegrees(from: route[j], to: route[i])
    }
}
