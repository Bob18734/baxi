import SwiftUI

/// How early Baxi warns, the voice, driver details for the official log, and the fine print (the 50-hour law,
/// where the data comes from, privacy). Opened from Home; nothing here is needed to drive.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @AppStorage("didFinishWelcome") private var didFinishWelcome = false
    @AppStorage(Speaker.rateKey) private var rate = 1.0
    @AppStorage(DriveSession.detailKey) private var detail = "everything"
    @State private var speaker: Speaker?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetHeader(title: "Settings") { dismiss() }
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s32) {
                        levels
                        voice
                        VStack(alignment: .leading, spacing: 0) {
                            GroupLabel("Driving log").padding(.bottom, Space.s4)
                            NavigationLink { DriverDetailsPage() } label: {
                                Row(title: "Driver details for export", detail: "Name and license number on the official form", showsDivider: false) { RowArrow() }
                            }
                            .buttonStyle(Press())
                        }
                        about
                        demoStates
                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.bottom, Space.s32)
                }
            }
            .pageBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var levels: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("How early Baxi warns you").padding(.bottom, Space.s4)
            ForEach(Array(ExperienceLevel.allCases.enumerated()), id: \.element) { i, level in
                Button { Haptic.tap(); withAnimation(Motion.quick) { store.level = level } } label: {
                    Row(title: level.title, detail: level.summary, showsDivider: i < ExperienceLevel.allCases.count - 1) {
                        Mark(glyph: .check, size: MarkSize.inline, weight: MarkWeight.emphasis).foregroundStyle(Palette.goText)
                            .opacity(store.level == level ? 1 : 0)
                    }
                }
                .buttonStyle(Press())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(store.level == level ? [.isButton, .isSelected] : .isButton)
            }
            Text("Timing only. What Baxi tells you to do is the same at every level.")
                .role(.meta).foregroundStyle(Palette.meta).padding(.top, Space.s8)
        }
    }

    private var voice: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("What Baxi says").padding(.bottom, Space.s4)
            choice("Everything", "Directions, plus speed limits, school zones, stop signs, crash-heavy spots and low sun.",
                   selected: detail != "directions") { detail = "everything" }
            choice("Just directions", "Only what to do at each turn, lane, roundabout, ramp and railroad. The screen still shows the rest.",
                   selected: detail == "directions", divider: false) { detail = "directions" }
            Text("The practice routes use Baxi's recorded voice. Searched routes use the iPhone's voice, \(Speaker.voiceDescription.name).")
                .role(.meta).foregroundStyle(Palette.meta).fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s12)
            if Speaker.voiceDescription.isBasic {
                NavigationLink { AboutPage(title: "A more natural voice", paragraphs: Self.voiceHelp) } label: {
                    Row(title: "Get a more natural voice", detail: "For searched routes", showsDivider: false) { RowArrow() }
                }
                .buttonStyle(Press())
            }
            VStack(alignment: .leading, spacing: Space.s8) {
                HStack {
                    Text("Speaking speed").role(.body).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(rate < 0.95 ? "Slower" : rate > 1.05 ? "Faster" : "Normal").role(.meta).foregroundStyle(Palette.meta)
                }
                Slider(value: $rate, in: 0.8...1.2, step: 0.05) { Text("Speaking speed") }
                    .tint(Palette.go)
                    .accessibilityValue(rate < 0.95 ? "Slower" : rate > 1.05 ? "Faster" : "Normal")
            }
            .padding(.top, Space.s16)
            BigButton(title: "Hear a cue", kind: .secondary, glyph: .speaker) {
                if speaker == nil { speaker = Speaker() }
                speaker?.say("In 500 feet, at the roundabout, take the second exit. Either lane works")
            }
            .padding(.top, Space.s16)
        }
    }

    /// A choice row with a check, the same as the warning levels.
    private func choice(_ title: String, _ detail: String, selected: Bool, divider: Bool = true, pick: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); withAnimation(Motion.quick) { pick() } } label: {
            Row(title: title, detail: detail, showsDivider: divider) {
                Mark(glyph: .check, size: MarkSize.inline, weight: MarkWeight.emphasis).foregroundStyle(Palette.goText)
                    .opacity(selected ? 1 : 0)
            }
        }
        .buttonStyle(Press())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// For showing Baxi off: the states a driver goes through, one tap each, with made-up drives that can be removed.
    private var demoStates: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Show the app's states").padding(.bottom, Space.s4)
            Text("For demos. Each one sets the level and swaps in sample drives; the drives you logged yourself stay, and the samples can be removed below.")
                .role(.meta).foregroundStyle(Palette.meta).fixedSize(horizontal: false, vertical: true).padding(.bottom, Space.s8)
            ForEach(DemoState.allCases) { state in
                Button { show(state) } label: {
                    Row(title: state.title, detail: state.detail) { RowArrow() }
                }
                .buttonStyle(Press())
            }
            Button { Haptic.tap(); withAnimation(Motion.quick) { store.demoNight.toggle() } } label: {
                Row(title: "Drive screen at night", detail: "The next drives use the night look whatever the clock says") {
                    Mark(glyph: .check, size: MarkSize.inline, weight: MarkWeight.emphasis).foregroundStyle(Palette.goText)
                        .opacity(store.demoNight ? 1 : 0)
                }
            }
            .buttonStyle(Press())
            .accessibilityAddTraits(store.demoNight ? [.isButton, .isSelected] : .isButton)
            Button {
                Haptic.tap()
                DemoStates.removeSamples(context)
                toasts.show("Sample drives removed. Your own drives are still here.")
            } label: {
                Row(title: "Remove sample drives", detail: "Keeps the drives you logged yourself", showsDivider: false) { EmptyView() }
            }
            .buttonStyle(Press())
        }
    }

    /// Settings closes first, so Home (or the welcome pages) appear with the new state.
    private func show(_ state: DemoState) {
        Haptic.success()
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            DemoStates.apply(state, store: store, context: context)
            store.tab = .home
            if state == .firstLaunch { didFinishWelcome = false } else { toasts.show("Showing: \(state.title.lowercased())") }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("About").padding(.bottom, Space.s4)
            ForEach([("The 50 supervised hours", Self.hours), ("Where Baxi's information comes from", Self.sources), ("Privacy", Self.privacy)],
                    id: \.0) { title, paragraphs in
                NavigationLink { AboutPage(title: title, paragraphs: paragraphs) } label: {
                    Row(title: title) { RowArrow() }
                }
                .buttonStyle(Press())
            }
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Road data").role(.rowTitle).foregroundStyle(Palette.ink)
                Group {
                    if store.cache == nil && store.isLoading { Text("Loading…") }
                    else { Text(store.dataStatus) }
                    // A searched route brings its own lanes, roundabouts and lights from OpenStreetMap.
                    if !store.routeOptions.isEmpty && store.roadDataNote == nil { Text("Plus the roads along your searched route.") }
                }
                .role(.meta).foregroundStyle(Palette.meta)
            }
            .padding(.vertical, Space.s12)
            .accessibilityElement(children: .combine)
        }
    }

    static let voiceHelp = [
        "Searched routes are spoken by the iPhone's own voice. The basic one sounds robotic; Ava (Premium) is far more natural, and free.",
        "On the iPhone, open Settings, then Accessibility, Spoken Content, Voices, English, and download Ava (Premium). Then reopen Baxi.",
    ]
    static let hours = [
        "Indiana requires 50 hours of supervised driving, 10 of them at night, before a new driver can get a license (IC 9-24-3-2.5).",
        "Every live drive in Baxi is logged with its start, end and miles. Replays of the practice routes are demos and never count.",
        "Baxi counts night from sunset to sunrise where the drive started. The law does not define night, so this is our reading.",
        "Export the official State Form 54706 from the Log. Review the entries and complete the applicable checkbox, affirmation and signatures on paper. Driver details for export are optional and saved on this device.",
    ]
    static let sources = [
        "Roads, lanes, roundabouts, lights, stop signs and speed limits: OpenStreetMap contributors (ODbL). Carmel's are built into the app; other routes download theirs when you plan them.",
        "Routes: the public OSRM route server, with Apple Maps as a backup. Weather: the National Weather Service.",
        "Crash-heavy roads and intersections: the Indianapolis MPO High Injury Network and Intersection Safety Studies. Fatal crashes: NHTSA FARS 2023, shown in Preview only.",
        "What to do at each kind of road: the Indiana Driver's Manual. How early Baxi warns you is Baxi's own design, as are the practice goals, levels and driving-habit coaching.",
        "The practice routes' voice: recorded on the team's Mac with Kokoro, an open-source voice model. Sign lettering: Overpass, after the US highway sign alphabet (SIL Open Font License).",
    ]
    static let privacy = [
        "Baxi uses your location during a drive, and once on the Routes screen so a searched route starts where you are, unless you choose a starting point. Drives are saved on this phone only; there is no account.",
        "A destination search goes to Apple Maps with your location, to find places nearby. A new route sends its start (where you are) and end to the OSRM route server (or Apple, if it is down), then its path, minus the first and last 200 m, to OpenStreetMap for its road details.",
        "The weather comes from the National Weather Service for the route's start, rounded to about 1 km.",
        "During a drive nothing is sent, except to find a new route if you leave this one.",
    ]
}

/// A page of fine print, pushed from Settings.
private struct AboutPage: View {
    let title: String
    let paragraphs: [String]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: title) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s16) {
                    ForEach(paragraphs, id: \.self) { p in
                        Text(p).role(.body).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.s32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A pushed page's top: back, then the title.
struct BackHeader: View {
    let title: String
    let back: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            MarkButton(glyph: .back, label: "Back", action: back).padding(.leading, -Space.s12)
            Text(title).role(.screenTitle).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s8)
        .padding(.bottom, Space.s16)
    }
}

/// Driver details pushed from Settings.
private struct DriverDetailsPage: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BackHeader(title: "Driver details") { dismiss() }
            DriverDetailsView()
        }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}
