import Foundation
import Observation

/// App-wide state: the loaded road data, the experience level, the chosen route.
/// Kept small on purpose; drives live in SwiftData.
@Observable
final class AppStore {
    var level: ExperienceLevel = .gettingComfortable
    var home: Coordinate? = nil
    var homeLabel: String = ""
    var cache: OSMCache?
    var features: [RoadFeature] = []
    var highInjury: HighInjuryNetwork?
    var dataStatus: String = "No area loaded"
    var isLoading = false

    var route: PlannedRoute?
    var routeError: String?

    /// Carmel City Center: the demo home point and the start of every preset route.
    static let carmelDemoHome = Coordinate(lat: 39.9765, lon: -86.1281)

    func loadCarmelDemo() {
        guard cache == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let c = try BundledData.carmelCache()
            cache = c
            features = FeatureExtractor.extract(from: c)
            highInjury = try? BundledData.highInjuryNetwork()
            home = Self.carmelDemoHome
            homeLabel = "Carmel City Center (demo)"
            let roundabouts = features.filter { [.singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout].contains($0.kind) }.count
            dataStatus = "Carmel: \(roundabouts) roundabouts, road data from OpenStreetMap \(c.fetched.prefix(10))"
        } catch {
            dataStatus = "Could not load the Carmel data: \(error)"
        }
    }

    func choosePreset(_ id: String) {
        loadCarmelDemo()
        do { route = try RouteService.preset(id); routeError = nil }
        catch { routeError = "Could not load that route: \(error)" }
    }

    func routeTo(_ destination: Coordinate, name: String) async {
        loadCarmelDemo()
        do { route = try await RouteService.route(from: home ?? Self.carmelDemoHome, to: destination, name: name); routeError = nil }
        catch { routeError = "No route found: \(error.localizedDescription)" }
    }

    func makeSession(replay: Double?) -> DriveSession? {
        guard let route, let cache else { return nil }
        return DriveSession(route: route, cache: cache, features: features, highInjury: highInjury, level: level,
                            mode: replay.map { .replay(speedMultiplier: $0) } ?? .live)
    }
}
