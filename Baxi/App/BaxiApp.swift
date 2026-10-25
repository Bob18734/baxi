import SwiftUI
import SwiftData

@main
struct BaxiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Palette.ink)
                // One identity, light. The Drive screen alone draws its own night (docs/DESIGN.md).
                .preferredColorScheme(.light)
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

    @AppStorage("didFinishWelcome") private var didFinishWelcome = false


    /// Launched with --demo-drive or --skip-welcome: never show the welcome sheet, so it cannot
    /// collide with the drive's full-screen cover.
    static let launchedForDemo = ProcessInfo.processInfo.arguments.contains { $0 == "--demo-drive" || $0 == "--skip-welcome" }

    var body: some View {
        #if DEBUG
        if let screen = ScreenCheck.value("--screen") {
            ScreenCheckRoot(screen: screen).environment(store).environment(toasts)
        } else { tabs }
        #else
        tabs
        #endif
    }

    @State private var toasts = ToastCenter()
    /// The bar steps aside while the keyboard is up (typing a search), as a system tab bar does.
    @State private var keyboardUp = false

    /// The three tabs stay alive while hidden (the Routes map keeps its place); the bar sits under them,
    /// and content ends where the bar begins.
    private func tab<V: View>(_ t: AppTab, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .opacity(store.tab == t ? 1 : 0)
            .allowsHitTesting(store.tab == t)
            .accessibilityHidden(store.tab != t)
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            ZStack {
                tab(.home) { HomeView() }
                tab(.route) { RouteView() }
                tab(.log) { LogView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !keyboardUp { BottomBar(selection: Bindable(store).tab).transition(.opacity) }
        }
        .animation(Motion.quick, value: keyboardUp)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .overlay(alignment: .bottom) {
            if let t = toasts.current {
                ToastView(toast: t) { toasts.runAction() }
                    .padding(.bottom, Size.bar + Space.s12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(store)
        .environment(toasts)
        .fullScreenCover(item: Bindable(store).activeSession) { s in
            DriveView(session: s) { store.activeSession = nil }.environment(toasts)
        }
        .sheet(isPresented: .constant(!didFinishWelcome && !Self.launchedForDemo)) {
            WelcomeView { didFinishWelcome = true }.environment(store).interactiveDismissDisabled()
        }
        .onAppear {
            #if DEBUG
            ScreenCheck.run()
            ScreenCheck.addSampleDrives(context)
            #endif
            let args = ProcessInfo.processInfo.arguments
            func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
            if args.contains("--carmel-demo") {
                store.loadCarmelDemo()
                store.tab = .route
            }
            if args.contains("--skip-welcome") { didFinishWelcome = true }
            if args.contains("--reset-welcome") { didFinishWelcome = false }
            if let preset = value("--route") { store.choosePreset(preset); store.tab = .route }
            switch value("--tab") { case "route": store.tab = .route; case "log": store.tab = .log; default: break }
            if let preset = value("--demo-drive") {
                didFinishWelcome = true
                store.tab = .route
                store.startDemoDrive(preset: preset, speed: value("--replay-speed").flatMap(Double.init) ?? 4,
                                     startMeters: value("--replay-start").flatMap(Double.init))
            }
        }
    }
}
