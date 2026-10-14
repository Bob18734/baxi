import Foundation
import Observation
import CoreLocation

/// App-wide state: the loaded road data, the experience level, the chosen route.
/// Kept small on purpose; drives live in SwiftData.
@MainActor
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

    /// Starts loading the bundled Carmel data in the background (decoding and feature extraction take a
    /// noticeable moment); safe to call again.
    func loadCarmelDemo() { Task { await ensureLoaded() } }

    /// Loads the bundled road data once, off the main thread; later calls wait for the same load.
    @MainActor func ensureLoaded() async {
        if cache != nil { return }
        if let loading = loadTask { await loading.value; return }
        isLoading = true
        let task = Task { @MainActor in
            let loaded = await Task.detached(priority: .userInitiated) { () -> (OSMCache, [RoadFeature], HighInjuryNetwork?)? in
                guard let c = try? BundledData.carmelCache() else { return nil }
                return (c, FeatureExtractor.extract(from: c), try? BundledData.highInjuryNetwork())
            }.value
            if let (c, f, hin) = loaded {
                cache = c; features = f; highInjury = hin
                home = Self.carmelDemoHome
                homeLabel = "Carmel City Center (demo)"
                let roundabouts = f.filter { [.singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout].contains($0.kind) }.count
                dataStatus = "Carmel: \(roundabouts) roundabouts, road data from OpenStreetMap \(c.fetched.prefix(10))"
            } else {
                dataStatus = "The Carmel road data did not load. Reinstall Baxi; it ships inside the app."
            }
            isLoading = false
        }
        loadTask = task
        await task.value
        if route != nil { refreshPrep() }
        Task { await buildPresetSkills() }
    }
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// The chosen route's cues, lights, limits and hard spots, built in the background. nil while building.
    private(set) var prep: RoutePrep?
    var isPreparing: Bool { route != nil && prep?.routeId != route?.id }
    @ObservationIgnored private var prepTask: Task<Void, Never>?

    /// Rebuilds `prep` for the current route, off the main thread. A newer route cancels an older build.
    @MainActor func refreshPrep() {
        guard let route else { prep = nil; return }
        if prep?.routeId == route.id { return }
        prepTask?.cancel()
        prepTask = Task { @MainActor in
            await ensureLoaded()
            guard let cache, !Task.isCancelled else { return }
            let (f, hin) = (features, highInjury)
            let built = await Task.detached(priority: .userInitiated) {
                RoutePrep.make(route: route, cache: cache, features: f, highInjury: hin)
            }.value
            if !Task.isCancelled, self.route?.id == built.routeId { prep = built }
        }
    }

    func choosePreset(_ id: String) {
        do { route = try RouteService.preset(id); routeError = nil }
        catch { routeError = "That practice route did not load."; print("Preset \(id) failed: \(error)") }
        refreshPrep()
    }

    func routeTo(_ destination: Coordinate, name: String) async {
        await ensureLoaded()
        defer { refreshPrep() }
        do { route = try await RouteService.route(from: home ?? Self.carmelDemoHome, to: destination, name: name); routeError = nil }
        catch {
            routeError = "No route found. Check the internet connection and try again, or pick a practice route."
            print("Routing failed: \(error)")
        }
    }

    /// The skills each preset route contains, for suggesting what to drive next. Built in the background
    /// once the road data is loaded; empty until then.
    private(set) var presetSkills: [(id: String, skills: SkillCounts)] = []

    @MainActor private func buildPresetSkills() async {
        guard presetSkills.isEmpty, let cache else { return }
        let f = features
        presetSkills = await Task.detached(priority: .utility) {
            RouteService.presets.compactMap { p -> (id: String, skills: SkillCounts)? in
                guard let r = try? RouteService.preset(p.id) else { return nil }
                let speeds = CueListBuilder.speedProfile(line: r.polyline, cache: cache)
                return (p.id, Practice.count(maneuvers: r.maneuvers, features: f,
                                             fastMeters: Practice.fastMeters(route: r.polyline.lengthMeters, speeds: speeds)))
            }
        }.value
    }

    /// The hard spots on the chosen route, for the Preview screen. Empty until the route's prep is built.
    func hardSpots() -> [HardSpot] {
        guard let route, let prep, prep.routeId == route.id else { return [] }
        return prep.spots
    }

    /// Starts a replay once the road data and the route's prep are ready (both build in the background).
    @MainActor func startDemoDrive(preset: String = AppStore.demoPreset, speed: Double = 4,
                                   startMeters: Double? = AppStore.demoStartMeters) {
        choosePreset(preset)
        Task { @MainActor in
            await ensureLoaded()
            await prepTask?.value
            activeSession = makeSession(replay: speed)
            if let startMeters { activeSession?.skip(toMeters: startMeters) }
        }
    }

    func makeSession(replay: Double?) -> DriveSession? {
        guard let route, let cache else { return nil }
        let mode: DriveSession.Mode = replay.map { .replay(speedMultiplier: $0) } ?? .live
        #if DEBUG && targetEnvironment(macCatalyst)
        // The Mac copy is only for screenshots; keep it quiet.
        return DriveSession(route: route, cache: cache, features: features, highInjury: highInjury, level: level,
                            mode: mode, speaker: SilentSpeech(), prep: prep)
        #else
        return DriveSession(route: route, cache: cache, features: features, highInjury: highInjury, level: level,
                            mode: mode, prep: prep)
        #endif
    }
}
