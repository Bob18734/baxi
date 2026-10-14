import Foundation
import Observation
import CoreLocation

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
    /// The drive on screen, if any. RootView presents it full screen.
    var activeSession: DriveSession?
    /// Lives as long as the app, so the permission prompt is not torn down with the welcome sheet.
    @ObservationIgnored let locationPermission = CLLocationManager()

    /// The judge demo: the US 31 loop replayed at 4x, starting just before the merge onto the highway,
    /// so a merge, two exit ramps, the interchange roundabout and multi-lane roundabouts happen in about three minutes.
    static let demoPreset = "preset_highway"
    static let demoStartMeters = 4_400.0

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
            dataStatus = "The Carmel road data did not load. Reinstall Baxi; it ships inside the app."
            print("Carmel cache failed: \(error)")
        }
    }

    func choosePreset(_ id: String) {
        loadCarmelDemo()
        do { route = try RouteService.preset(id); routeError = nil }
        catch { routeError = "That practice route did not load."; print("Preset \(id) failed: \(error)") }
    }

    func routeTo(_ destination: Coordinate, name: String) async {
        loadCarmelDemo()
        do { route = try await RouteService.route(from: home ?? Self.carmelDemoHome, to: destination, name: name); routeError = nil }
        catch {
            routeError = "No route found. Check the internet connection and try again, or pick a practice route."
            print("Routing failed: \(error)")
        }
    }

    /// The skills each preset route contains, for suggesting what to drive next (built once).
    func presetSkills() -> [(id: String, skills: SkillCounts)] {
        if let presetSkillsCache { return presetSkillsCache }
        guard let cache else { return [] }
        let built = RouteService.presets.compactMap { p -> (id: String, skills: SkillCounts)? in
            guard let r = try? RouteService.preset(p.id) else { return nil }
            let speeds = CueListBuilder.speedProfile(line: r.polyline, cache: cache)
            return (p.id, Practice.count(maneuvers: r.maneuvers, features: features,
                                         fastMeters: Practice.fastMeters(route: r.polyline.lengthMeters, speeds: speeds)))
        }
        presetSkillsCache = built
        return built
    }
    @ObservationIgnored private var presetSkillsCache: [(id: String, skills: SkillCounts)]?

    /// The hard spots on the chosen route, for the Preview screen.
    func hardSpots() -> [HardSpot] {
        guard let route, let cache else { return [] }
        let cues = CueListBuilder.build(route: route, cache: cache, features: features, highInjury: highInjury)
        return HardSpots.find(route: route, cues: cues, features: features)
    }

    func startDemoDrive(speed: Double = 4, startMeters: Double = AppStore.demoStartMeters) {
        choosePreset(Self.demoPreset)
        activeSession = makeSession(replay: speed)
        activeSession?.skip(toMeters: startMeters)
    }

    func makeSession(replay: Double?) -> DriveSession? {
        guard let route, let cache else { return nil }
        let mode: DriveSession.Mode = replay.map { .replay(speedMultiplier: $0) } ?? .live
        #if DEBUG && targetEnvironment(macCatalyst)
        // The Mac copy is only for screenshots; keep it quiet.
        return DriveSession(route: route, cache: cache, features: features, highInjury: highInjury, level: level,
                            mode: mode, speaker: SilentSpeech())
        #else
        return DriveSession(route: route, cache: cache, features: features, highInjury: highInjury, level: level,
                            mode: mode)
        #endif
    }
}
