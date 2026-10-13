import Foundation

/// The five-step skill ladder. A driver unlocks the next tier after three clean passes
/// of every feature kind in the current one (see Progression.swift).
enum Tier: Int, Codable, CaseIterable, Comparable, Identifiable {
    case neighborhood = 1
    case signalsAndSingleLane = 2
    case multiLaneRoundabouts = 3
    case parkways = 4
    case highway = 5

    var id: Int { rawValue }
    static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .neighborhood: "Neighborhood"
        case .signalsAndSingleLane: "Signals and single-lane roundabouts"
        case .multiLaneRoundabouts: "Multi-lane roundabouts"
        case .parkways: "Parkways and interchanges"
        case .highway: "Highway ramps and merges"
        }
    }

    var summary: String {
        switch self {
        case .neighborhood: "Streets at 30 mph or less, stop signs, right turns."
        case .signalsAndSingleLane: "Traffic signals, one-lane roundabouts, school zones. Night driving unlocks here."
        case .multiLaneRoundabouts: "Two-lane roundabouts and roads posted 40 to 45 mph."
        case .parkways: "Parkways, interchange roundabouts, 50 mph, crash-corridor warnings."
        case .highway: "Highway ramps and merges at 55 to 65 mph."
        }
    }

    /// Search radius around home for route features, in meters.
    var searchRadiusMeters: Double {
        switch self {
        case .neighborhood: 3000
        case .signalsAndSingleLane: 4000
        case .multiLaneRoundabouts: 5500
        case .parkways: 7000
        case .highway: 8000
        }
    }

    var nightAllowed: Bool { self >= .signalsAndSingleLane }
    var next: Tier? { Tier(rawValue: rawValue + 1) }
}
