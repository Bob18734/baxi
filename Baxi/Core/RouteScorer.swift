import Foundation

// OWNER: partner. First of the partner's two modules. Tests: BaxiTests/RouteScorerTests.swift.

/// A candidate loop after routing and feature matching, ready to be scored.
struct ScoredCandidate: Identifiable {
    let id: String
    let durationMinutes: Double
    let distanceMeters: Double
    /// Features within 25 m of the route line, in route order.
    let features: [RoadFeature]
    /// True when any part of the route runs along a High Injury Network corridor.
    let touchesHighInjuryCorridor: Bool
}

struct RouteScore: Equatable {
    let total: Double
    /// Short lines a judge or a parent can read: "+3 two-lane roundabouts (tier 3)", "-10 above-tier highway ramp".
    let reasons: [String]
}

enum RouteScorer {
    /// Rules the tests check:
    /// 1. +3 per feature whose tier equals the driver's tier.
    /// 2. +1 per feature one tier below the driver's tier (review), 0 for anything lower.
    /// 3. -10 per feature above the driver's tier.
    /// 4. -1 per minute the duration falls outside 20 to 30 minutes.
    /// 5. -25 when touchesHighInjuryCorridor is true and the driver's tier is below .parkways.
    /// 6. reasons has one line per rule that fired, in the order above.
    static func score(_ candidate: ScoredCandidate, tier: Tier) -> RouteScore {
        // STUB. Replace with the partner's implementation.
        let onTier = candidate.features.filter { $0.tier == tier }.count
        return RouteScore(total: Double(onTier) * 3, reasons: ["Stub score. Partner's scorer replaces this."])
    }
}
