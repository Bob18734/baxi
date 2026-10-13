import SwiftUI
import SwiftData

@main
struct FirstRoadsApp: App {
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

    enum AppTab { case home, plan, log }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: .home) { HomeView() }
            Tab("Plan", systemImage: "map.fill", value: .plan) { PlanView() }
            Tab("Log", systemImage: "list.bullet.clipboard.fill", value: .log) { LogView() }
        }
        .environment(store)
        .onAppear {
            // `--carmel-demo` loads the bundled demo and opens the map. Used for screenshots and the video.
            if ProcessInfo.processInfo.arguments.contains("--carmel-demo") {
                store.loadCarmelDemo()
                tab = .plan
            }
        }
    }
}
