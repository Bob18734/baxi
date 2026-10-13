import Foundation

/// What kind of thing on the road a driver has to handle. Each kind belongs to one tier.
enum FeatureKind: String, Codable, CaseIterable, Identifiable {
    case stopSign
    case trafficSignal
    case schoolZone
    case singleLaneRoundabout
    case multiLaneRoundabout
    case interchangeRoundabout
    case road40to45
    case road50
    case highwayRamp

    var id: String { rawValue }

    var tier: Tier {
        switch self {
        case .stopSign: .neighborhood
        case .trafficSignal, .schoolZone, .singleLaneRoundabout: .signalsAndSingleLane
        case .multiLaneRoundabout, .road40to45: .multiLaneRoundabouts
        case .interchangeRoundabout, .road50: .parkways
        case .highwayRamp: .highway
        }
    }

    var label: String {
        switch self {
        case .stopSign: "Stop sign"
        case .trafficSignal: "Traffic signal"
        case .schoolZone: "School zone"
        case .singleLaneRoundabout: "Single-lane roundabout"
        case .multiLaneRoundabout: "Multi-lane roundabout"
        case .interchangeRoundabout: "Interchange roundabout"
        case .road40to45: "40 to 45 mph road"
        case .road50: "50 mph road"
        case .highwayRamp: "Highway ramp"
        }
    }

    var symbolName: String {
        switch self {
        case .stopSign: "octagon.fill"
        case .trafficSignal: "light.beacon.max.fill"
        case .schoolZone: "figure.walk"
        case .singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout: "arrow.triangle.2.circlepath"
        case .road40to45, .road50: "gauge.with.dots.needle.50percent"
        case .highwayRamp: "arrow.merge"
        }
    }
}

/// One typed, located thing the app can route past, brief, and score.
struct RoadFeature: Codable, Identifiable, Hashable {
    let id: String
    let kind: FeatureKind
    let coordinate: Coordinate
    let name: String?
    /// Lanes in the circulatory roadway (roundabouts) or on the road.
    let lanes: Int?
    /// Legs entering or leaving a roundabout.
    let legs: Int?
    let maxspeedMph: Int?
    /// OSM way or node ids this feature was built from, for citations and debugging.
    let osmIds: [Int]

    var tier: Tier { kind.tier }
}
