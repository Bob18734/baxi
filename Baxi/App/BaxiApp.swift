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

    @State private var demoSession: DriveSession?

    enum AppTab { case home, route, log }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: .home) { HomeView() }
            Tab("Route", systemImage: "map.fill", value: .route) { RouteView() }
            Tab("Log", systemImage: "list.bullet.clipboard.fill", value: .log) { LogView() }
        }
        .environment(store)
        .fullScreenCover(item: $demoSession) { s in DriveView(session: s) { demoSession = nil } }
        .onAppear {
            // Launch arguments for screenshots, testing and the video:
            //   --carmel-demo                 load Carmel and open the Route tab
            //   --demo-drive <preset id>      start a replayed drive on that preset right away
            //   --replay-speed <n>            replay clock multiplier (default 4)
            //   --replay-start <meters>       skip ahead along the route before starting
            let args = ProcessInfo.processInfo.arguments
            func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
            if args.contains("--carmel-demo") {
                store.loadCarmelDemo()
                tab = .route
            }
            if let preset = value("--demo-drive") {
                store.choosePreset(preset)
                tab = .route
                let speed = value("--replay-speed").flatMap(Double.init) ?? 4
                demoSession = store.makeSession(replay: speed)
                if let start = value("--replay-start").flatMap(Double.init) { demoSession?.skip(toMeters: start) }
            }
        }
    }
}
