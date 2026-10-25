import Foundation
import Observation
import CoreLocation
import os

/// App-wide state: the loaded road data, the experience level, the chosen route.
/// Kept small on purpose; drives live in SwiftData.
enum AppTab { case home, route, log }

@MainActor
@Observable
final class AppStore {
    /// The tab on screen, so Home can send the driver to Routes or the Log.
    var tab: AppTab = .home
    /// Set by Home's "Where to?" field: Routes opens with its search field active.
    var wantsSearch = false
    /// Remembered between launches (Settings > Experience).
    var level: ExperienceLevel = ExperienceLevel(rawValue: UserDefaults.standard.string(forKey: AppStore.levelKey) ?? "")
        ?? .gettingComfortable {
        didSet { UserDefaults.standard.set(level.rawValue, forKey: Self.levelKey) }
    }
    nonisolated static let levelKey = "experienceLevel"
    nonisolated static let log = Logger(subsystem: "com.vardaangoel.Baxi", category: "routes")
    /// Where a searched route starts: the phone's last known position, else Carmel City Center.
    private(set) var origin: Coordinate = RouteService.carmelCityCenter
    /// True once `origin` is the phone's own position.
    private(set) var originIsHere = false
    /// What a route search is doing right now, shown under the loading shimmer. nil when idle.
    private(set) var routeStep: String?
    /// From the demo button's tap until the demo drive is on screen.
    private(set) var isStartingDemo = false
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
    nonisolated static let demoPreset = "preset_highway"
    nonisolated static let demoStartMeters = 4_400.0

    /// Carmel City Center: the demo home point and the start of every preset route.
    nonisolated static let carmelDemoHome = RouteService.carmelCityCenter

    /// Asks for one location fix and makes it the start of searched routes. Keeps the last good one
    /// when no new fix comes.
    func refreshOrigin() async {
        // The first time, the permission prompt is on screen: give the person time to answer it.
        let undecided = locationPermission.authorizationStatus == .notDetermined
        guard let fix = await CurrentLocation.once(timeout: undecided ? 30 : 4) else { return }
        origin = RouteService.origin(fix: fix)
        originIsHere = true
    }

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
    /// Weather at the start of the chosen route (National Weather Service), nil until it loads or offline.
    private(set) var weather: RoadWeather?
    @ObservationIgnored private var weatherFetched: (key: String, at: Date)?

    /// Fetches the weather for the route's start, at most every 15 minutes per place.
    @MainActor private func refreshWeather(for route: PlannedRoute) {
        guard let start = route.polyline.points.first else { return }
        let key = String(format: "%.2f,%.2f", start.lat, start.lon)
        if let f = weatherFetched, f.key == key, Date().timeIntervalSince(f.at) < 900 { return }
        weatherFetched = (key, Date())
        Task { @MainActor in weather = try? await WeatherService.weather(at: start) }
    }

    @MainActor func refreshPrep() {
        guard let route else { prep = nil; return }
        refreshWeather(for: route)
        if prep?.routeId == route.id { return }
        prepTask?.cancel()
        prepTask = Task { @MainActor in
            await ensureLoaded()
            guard let (cache, f) = roads, !Task.isCancelled else { return }
            let hin = highInjury
            let built = await Task.detached(priority: .userInitiated) {
                RoutePrep.make(route: route, cache: cache, features: f, highInjury: hin)
            }.value
            if !Task.isCancelled, self.route?.id == built.routeId { prep = built }
        }
    }

    func choosePreset(_ id: String) {
        do { route = try RouteService.preset(id); routeError = nil; roadDataNote = nil; routeOptions = []; calmerOptionId = nil }
        catch { routeError = "That practice route did not load."; Self.log.error("Preset \(id, privacy: .public) failed: \(error)") }
        refreshPrep()
    }

    /// Road data fetched along a searched route (OverpassService), merged with the bundled Carmel data.
    /// Presets use the bundled data alone.
    @ObservationIgnored private var routeRoads: (routeId: String, cache: OSMCache, features: [RoadFeature])?
    /// What Baxi knows about the roads on the chosen route, shown under the route when it matters.
    private(set) var roadDataNote: String?
    private(set) var isFetchingRoads = false

    /// The road data and features for the current route.
    private var roads: (cache: OSMCache, features: [RoadFeature])? {
        if let r = routeRoads, r.routeId == route?.id { return (r.cache, r.features) }
        return cache.map { ($0, features) }
    }

    /// The fastest route and, when one exists, a calmer one (less on fast, busy roads), for a searched
    /// destination. Empty for presets.
    private(set) var routeOptions: [RouteService.Option] = []
    private(set) var calmerOptionId: String?

    nonisolated static let roadDataSeconds = 25.0

    func routeTo(_ destination: Coordinate, name: String) async {
        await ensureLoaded()
        routeStep = "Finding a route…"
        defer { routeStep = nil }
        await refreshOrigin()
        do {
            let options = try await RouteService.options(from: origin, to: destination, name: name)
            routeError = nil
            routeOptions = options
            let calmer = RouteService.calmer(in: options)
            calmerOptionId = calmer?.id
            // New drivers start on the calmer route; everyone can switch.
            let pick = (level == .new ? calmer : nil) ?? options[0]
            await use(pick.route)
        } catch {
            routeError = "No route found. Check the internet connection and try again, or pick a practice route."
            Self.log.error("Routing failed: \(error)")
        }
    }

    /// Switches between the fastest and the calmer route.
    func chooseOption(_ id: String) async {
        guard let o = routeOptions.first(where: { $0.id == id }), o.id != route?.id else { return }
        await use(o.route)
    }

    /// Makes `found` the route: downloads its road data from OpenStreetMap first, then builds its prep.
    private func use(_ found: PlannedRoute) async {
        roadDataNote = nil
        isFetchingRoads = true
        routeStep = "Loading lanes and roundabouts…"
        let line = found.polyline
        // A slow map server must not hold the route: after this long, drive without lane details.
        let corridor = await Deadline.run(seconds: Self.roadDataSeconds) { try await OverpassService.corridor(along: line) }
        if let base = cache, let corridor {
            let merged = OverpassService.combine(base, corridor)
            let f = await Task.detached(priority: .userInitiated) { FeatureExtractor.extract(from: merged) }.value
            routeRoads = (found.id, merged, f)
        } else {
            roadDataNote = "Lane and roundabout details didn't load for this route (OpenStreetMap was slow or unreachable). "
                + "Turn-by-turn still works."
        }
        isFetchingRoads = false
        routeStep = nil
        route = found
        refreshPrep()
    }

    /// The skills each preset route contains, for suggesting what to drive next. Built in the background
    /// once the road data is loaded; empty until then.
    private(set) var presetSkills: [(id: String, skills: SkillCounts)] = []
    /// Each preset's length in meters, for Home's route signs.
    private(set) var presetMeters: [String: Double] = [:]

    @MainActor private func buildPresetSkills() async {
        guard presetSkills.isEmpty, let cache else { return }
        let f = features
        presetMeters = Dictionary(uniqueKeysWithValues: RouteService.presets.compactMap { p in
            (try? RouteService.preset(p.id)).map { (p.id, $0.distanceMeters) }
        })
        presetSkills = await Task.detached(priority: .utility) {
            RouteService.presets.compactMap { p -> (id: String, skills: SkillCounts)? in
                guard let r = try? RouteService.preset(p.id) else { return nil }
                let speeds = CueListBuilder.speedProfile(line: r.polyline, cache: cache)
                return (p.id, Practice.count(maneuvers: r.maneuvers, features: f,
                                             fastMeters: Practice.fastMeters(route: r.polyline.lengthMeters, speeds: speeds)))
            }
        }.value
    }

    /// Where to change lanes on the chosen route at the current level, with each zone's stretch of road,
    /// for the Routes map. Empty until the route's prep is built.
    var laneZones: [(zone: LaneZone, line: [CLLocationCoordinate2D])] {
        guard let route, let prep, prep.routeId == route.id else { return [] }
        let key = "\(route.id)|\(level.rawValue)"
        if let cached = zoneCache, cached.key == key { return cached.zones }
        let zones = LaneZones.build(cues: prep.planned(for: level, route: route), route: route).map {
            (zone: $0, line: route.polyline.slice(from: $0.startMeters, to: $0.endMeters).map(\.clLocation))
        }
        zoneCache = (key, zones)
        return zones
    }
    @ObservationIgnored private var zoneCache: (key: String, zones: [(zone: LaneZone, line: [CLLocationCoordinate2D])])?

    /// The hard spots on the chosen route, for the Preview screen. Empty until the route's prep is built.
    func hardSpots() -> [HardSpot] {
        guard let route, let prep, prep.routeId == route.id else { return [] }
        return (prep.spots + HardSpots.glare(route: route, start: Date())).sorted { $0.alongMeters < $1.alongMeters }
    }

    /// Starts a replay once the road data and the route's prep are ready (both build in the background).
    @MainActor func startDemoDrive(preset: String = AppStore.demoPreset, speed: Double = 4,
                                   startMeters: Double? = AppStore.demoStartMeters) {
        guard !isStartingDemo, activeSession == nil else { return }
        isStartingDemo = true
        choosePreset(preset)
        Task { @MainActor in
            await ensureLoaded()
            await prepTask?.value
            activeSession = makeSession(replay: speed)
            if let startMeters { activeSession?.skip(toMeters: startMeters) }
            isStartingDemo = false
        }
    }

    func makeSession(replay: Double?) -> DriveSession? {
        guard let route, let (cache, features) = roads else { return nil }
        let mode: DriveSession.Mode = replay.map { .replay(speedMultiplier: $0) } ?? .live
        #if DEBUG && targetEnvironment(macCatalyst)
        // The Mac copy is only for screenshots; keep it quiet.
        let s = DriveSession(route: route, cache: cache, features: features, highInjury: highInjury, level: level,
                             mode: mode, speaker: SilentSpeech(), prep: prep)
        s.weatherLine = weather?.spoken
        return s
        #else
        let s = DriveSession(route: route, cache: cache, features: features, highInjury: highInjury, level: level,
                             mode: mode, prep: prep)
        s.weatherLine = weather?.spoken
        return s
        #endif
    }
}
