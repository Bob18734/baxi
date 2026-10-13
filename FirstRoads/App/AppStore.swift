import Foundation
import Observation

/// App-wide state: the loaded road data, the home point, the driver's tier.
/// Kept small on purpose; drives live in SwiftData.
@Observable
final class AppStore {
    var tier: Tier = .multiLaneRoundabouts
    var home: Coordinate? = nil
    var homeLabel: String = ""
    var features: [RoadFeature] = []
    var dataStatus: String = "No area loaded"
    var isLoading = false

    /// Carmel City Center: the demo home point. Everything the demo needs is bundled.
    static let carmelDemoHome = Coordinate(lat: 39.9765, lon: -86.1281)

    func loadCarmelDemo() {
        isLoading = true
        defer { isLoading = false }
        do {
            let cache = try BundledData.carmelCache()
            features = FeatureExtractor.extract(from: cache)
            home = Self.carmelDemoHome
            homeLabel = "Carmel City Center (demo)"
            let roundabouts = features.filter { [.singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout].contains($0.kind) }.count
            dataStatus = "Carmel demo: \(features.count) features, \(roundabouts) roundabouts, OSM data from \(cache.fetched)"
        } catch {
            dataStatus = "Could not load the Carmel demo: \(error)"
        }
    }

    /// Features inside the current tier's search radius around home.
    var nearbyFeatures: [RoadFeature] {
        guard let home else { return [] }
        let r = tier.searchRadiusMeters
        return features.filter { Geo.distanceMeters(home, $0.coordinate) <= r }
    }

    func count(of kind: FeatureKind) -> Int { nearbyFeatures.filter { $0.kind == kind }.count }
}
