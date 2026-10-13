import Foundation

// OWNER: partner. Second of the partner's two modules. Tests: BaxiTests/ApproachHeadingTests.swift.

enum ApproachHeading {
    /// The compass bearing a driver faces when arriving at `spot` along `route`.
    /// Used to aim the Look Around camera on each walkthrough card.
    /// Rules the tests check:
    /// 1. Find the route point nearest the spot (call its index i).
    /// 2. Walk backwards from i until the walked distance is at least `lookBackMeters` (default 40) or the route starts; call that index j.
    /// 3. Return Geo.bearingDegrees(from: route[j], to: route[i]).
    /// 4. Fewer than two route points, or i == j (the spot is at the route start): return nil.
    static func bearing(route: [Coordinate], spot: Coordinate, lookBackMeters: Double = 40) -> Double? {
        // STUB. Replace with the partner's implementation.
        guard route.count >= 2 else { return nil }
        return Geo.bearingDegrees(from: route[route.count - 2], to: route[route.count - 1])
    }
}
