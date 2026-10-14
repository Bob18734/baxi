import SwiftUI
import SwiftData

@main
struct BaxiApp: App {
    init() { BaxiChrome.apply() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(BaxiColor.accent)
                #if DEBUG
                .transformEnvironment(\.dynamicTypeSize) { if ScreenCheck.bigText { $0 = .accessibility3 } }
                #endif
        }
        .modelContainer(for: [DriveRecord.self])
    }
}

struct RootView: View {
    @State private var store = AppStore()
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .home

    @AppStorage("didFinishWelcome") private var didFinishWelcome = false

    enum AppTab { case home, route, log }

    /// Launched with --demo-drive or --skip-welcome: never show the welcome sheet, so it cannot
    /// collide with the drive's full-screen cover.
    static let launchedForDemo = ProcessInfo.processInfo.arguments.contains { $0 == "--demo-drive" || $0 == "--skip-welcome" }

    var body: some View {
        #if DEBUG
        if let screen = ScreenCheck.value("--screen") {
            ScreenCheckRoot(screen: screen).environment(store)
        } else { tabs }
        #else
        tabs
        #endif
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "signpost.right.fill", value: .home) { HomeView() }
            Tab("Routes", systemImage: "map.fill", value: .route) { RouteView() }
            Tab("Log", systemImage: "clock.badge.checkmark.fill", value: .log) { LogView() }
        }
        .environment(store)
        .fullScreenCover(item: Bindable(store).activeSession) { s in DriveView(session: s) { store.activeSession = nil } }
        .sheet(isPresented: .constant(!didFinishWelcome && !Self.launchedForDemo)) {
            WelcomeView { didFinishWelcome = true }.environment(store).interactiveDismissDisabled()
        }
        .onAppear {
            // Launch arguments for screenshots, testing and the video:
            //   --carmel-demo                 load Carmel and open the Route tab
            //   --demo-drive <preset id>      start a replayed drive on that preset right away
            //   --replay-speed <n>            replay clock multiplier (default 4)
            //   --replay-start <meters>       skip ahead along the route before starting
            //   --skip-welcome                skip the first-launch safety screen
            //   --reset-welcome               show it again
            //   --tab route|log               open on that tab
            //   --route <preset id>           choose that practice route
            #if DEBUG
            ScreenCheck.run()
            ScreenCheck.addSampleDrives(context)
            #endif
            let args = ProcessInfo.processInfo.arguments
            func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
            if args.contains("--carmel-demo") {
                store.loadCarmelDemo()
                tab = .route
            }
            if args.contains("--skip-welcome") { didFinishWelcome = true }
            if args.contains("--reset-welcome") { didFinishWelcome = false }
            if let preset = value("--route") { store.choosePreset(preset); tab = .route }
            switch value("--tab") { case "route": tab = .route; case "log": tab = .log; default: break }
            if let preset = value("--demo-drive") {
                didFinishWelcome = true
                store.choosePreset(preset)
                tab = .route
                let speed = value("--replay-speed").flatMap(Double.init) ?? 4
                store.activeSession = store.makeSession(replay: speed)
                if let start = value("--replay-start").flatMap(Double.init) { store.activeSession?.skip(toMeters: start) }
            }
        }
    }
}
