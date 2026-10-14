#if DEBUG
import SwiftUI
import SwiftData
import UIKit

/// Debug only. Lets a Mac (Catalyst) build show and photograph screens, because the team's Mac
/// cannot run the iOS Simulator. Launch arguments:
///   --phone-window              size the Mac window like an iPhone 17 (393 x 852 points)
///   --snap <path.png>           after a few seconds, save the window to that file and quit
///   --snap-delay <seconds>      wait this long before the snapshot (default 4)
///   --appearance light|dark     force light or dark mode
///   --big-text                  the largest accessibility text size, to check layouts at XXXL
///   --spots <id prefix>         with --screen preview, only the spots whose id starts with this
enum ScreenCheck {
    static var bigText: Bool { args.contains("--big-text") }
    static let args = ProcessInfo.processInfo.arguments
    static func value(_ flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }

    @MainActor static func run() {
        #if targetEnvironment(macCatalyst)
        if args.contains("--phone-window") {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                let size = CGSize(width: 393, height: 852)
                scene.sizeRestrictions?.minimumSize = size
                scene.sizeRestrictions?.maximumSize = size
            }
        }
        #endif
        if let style = value("--appearance") {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.windows.forEach { $0.overrideUserInterfaceStyle = style == "dark" ? .dark : .light }
            }
        }
        guard let path = value("--snap") else { return }
        let delay = value("--snap-delay").flatMap(Double.init) ?? 4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
                .filter { !$0.isHidden }.sorted { $0.windowLevel < $1.windowLevel }
            guard let first = windows.first else { exit(2) }
            // Sheets can live in their own window, so draw every window, back to front.
            let image = UIGraphicsImageRenderer(bounds: first.bounds).image { _ in
                for w in windows { w.drawHierarchy(in: w.frame, afterScreenUpdates: true) }
            }
            try? image.pngData()?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}
#endif

#if DEBUG
/// `--screen welcome|preview|arrived` opens one screen on its own, filled with the highway demo route.
struct ScreenCheckRoot: View {
    let screen: String
    @Environment(AppStore.self) private var store
    @State private var session: DriveSession?

    var body: some View {
        ZStack {
            BaxiColor.page.ignoresSafeArea()
            switch screen {
            case "welcome": WelcomeView {}
            case "preview":
                if let r = store.route {
                    let only = ScreenCheck.value("--spots")   // e.g. "fars-" to shoot just those cards
                    PreviewView(routeName: r.name, spots: store.hardSpots().filter { only.map($0.id.hasPrefix) ?? true }, route: r) {}
                }
            case "arrived":
                if let session { ArrivedView(session: session, record: nil) {} }
            default: Text("Unknown screen \(screen)")
            }
        }
        .onAppear {
            ScreenCheck.run()
            store.choosePreset(AppStore.demoPreset)
            guard screen == "arrived" else { return }
            Task { @MainActor in
            await store.ensureLoaded()
            guard let route = store.route, let cache = store.cache else { return }
            let s = DriveSession(route: route, cache: cache, features: store.features, highInjury: store.highInjury,
                                 level: store.level, mode: .replay(speedMultiplier: 1), speaker: SilentSpeech())
            s.skip(toMeters: AppStore.demoStartMeters)
            _ = s.simulateWholeRoute()
            session = s
            }
        }
    }
}

extension ScreenCheck {
    /// `--sample-drives`: a few made-up drives so the Log can be photographed with rows in it.
    /// Debug only, and only when the log is empty.
    @MainActor static func addSampleDrives(_ context: ModelContext) {
        guard args.contains("--sample-drives"),
              (try? context.fetchCount(FetchDescriptor<DriveRecord>())) == 0 else { return }
        let day: TimeInterval = 86_400
        let samples: [(daysAgo: Double, minutes: Int, night: Int, title: String, manual: Bool)] = [
            (1, 42, 18, "Highway ramp loop", false), (2, 35, 0, "Roundabout loop", false),
            (4, 60, 0, "Practice drive", true), (9, 28, 28, "Parkway loop", false), (33, 50, 0, "Carmel Clay Library", false),
        ]
        for s in samples {
            let start = Date().addingTimeInterval(-s.daysAgo * day)
            context.insert(DriveRecord(start: start, end: start.addingTimeInterval(Double(s.minutes) * 60),
                                       dayMinutes: s.minutes - s.night, nightMinutes: s.night, level: .gettingComfortable,
                                       routeTitle: s.title, distanceMeters: s.manual ? 0 : Double(s.minutes) * 600,
                                       cuesSpoken: s.manual ? 0 : 20, manual: s.manual,
                                       skills: s.manual ? [:] : [.singleLaneRoundabout: 5, .multiLaneRoundabout: 2, .laneTurn: 1]))
        }
        try? context.save()
    }
}

/// Used for every drive in the Mac copy, which exists only for screenshots, so it never talks aloud.
final class SilentSpeech: SpeechOutput {
    var isMuted = false
    func say(_ text: String) {}
    func stop() {}
}
#endif
