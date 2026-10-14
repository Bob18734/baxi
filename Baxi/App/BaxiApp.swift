import SwiftUI
import SwiftData

@main
struct BaxiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [DriveRecord.self])
    }
}

struct RootView: View {
    @State private var store = AppStore()
    @State private var tab: AppTab = .home

    @AppStorage("didFinishWelcome") private var didFinishWelcome = false

    enum AppTab { case home, route, log }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: .home) { HomeView() }
            Tab("Route", systemImage: "map.fill", value: .route) { RouteView() }
            Tab("Log", systemImage: "list.bullet.clipboard.fill", value: .log) { LogView() }
        }
        .environment(store)
        .fullScreenCover(item: Bindable(store).activeSession) { s in DriveView(session: s) { store.activeSession = nil } }
        .sheet(isPresented: .constant(!didFinishWelcome)) {
            WelcomeView { didFinishWelcome = true }.interactiveDismissDisabled()
        }
        .onAppear {
            // Launch arguments for screenshots, testing and the video:
            //   --carmel-demo                 load Carmel and open the Route tab
            //   --demo-drive <preset id>      start a replayed drive on that preset right away
            //   --replay-speed <n>            replay clock multiplier (default 4)
            //   --replay-start <meters>       skip ahead along the route before starting
            //   --skip-welcome                skip the first-launch safety screen
            let args = ProcessInfo.processInfo.arguments
            func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
            if args.contains("--carmel-demo") {
                store.loadCarmelDemo()
                tab = .route
            }
            if args.contains("--skip-welcome") { didFinishWelcome = true }
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
