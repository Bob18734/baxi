import SwiftUI

/// How early Baxi warns, the voice, and the fine print (the 50-hour law, where the data comes from,
/// privacy). Opened from Home's gear button; nothing here is needed to drive.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Speaker.rateKey) private var rate = 1.0
    @AppStorage(DriveSession.detailKey) private var detail = "everything"
    @State private var speaker: Speaker?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ExperienceLevel.allCases) { level in
                        Button { withAnimation(.snappy) { store.level = level }; Haptics.tap() } label: { levelRow(level) }
                            .foregroundStyle(BaxiColor.ink)
                    }
                } header: {
                    Text("How early Baxi warns you")
                } footer: {
                    Text("Timing only. What Baxi tells you to do is the same at every level.")
                }

                Section {
                    Picker("Baxi says", selection: $detail) {
                        Text("Everything").tag("everything")
                        Text("Just directions").tag("directions")
                    }
                    LabeledContent("Voice", value: Speaker.voiceDescription.name)
                    VStack(alignment: .leading, spacing: BaxiSpace.sm) {
                        HStack {
                            Text("Speaking speed")
                            Spacer()
                            Text(rate < 0.95 ? "Slower" : rate > 1.05 ? "Faster" : "Normal").foregroundStyle(BaxiColor.inkSoft)
                        }
                        HStack(spacing: BaxiSpace.md) {
                            Image(systemName: "tortoise.fill").foregroundStyle(BaxiColor.inkFaint)
                            Slider(value: $rate, in: 0.8...1.2, step: 0.05)
                            Image(systemName: "hare.fill").foregroundStyle(BaxiColor.inkFaint)
                        }
                    }
                    Button {
                        if speaker == nil { speaker = Speaker() }
                        speaker?.say("Move to the right lane now for your turn, your turn is in 2 lights")
                    } label: { Label("Hear a cue", systemImage: "speaker.wave.2.fill") }
                } header: {
                    Text("Voice")
                } footer: {
                    Text(Speaker.voiceDescription.isBasic
                         ? "This is the basic voice. For a far more natural one, download Ava (Premium) in the iPhone's Settings > Accessibility > Spoken Content > Voices > English, then reopen Baxi."
                         : "\"Just directions\" leaves out speed, school, stop-sign, crash and low-sun lines; the screen still shows them.")
                }

                Section("Driving log") {
                    NavigationLink("Driver details for export") { DriverDetailsView() }
                }

                Section("About") {
                    NavigationLink("The 50 supervised hours") { AboutPage(title: "The 50 supervised hours", paragraphs: Self.hours) }
                    NavigationLink("Where Baxi's information comes from") { AboutPage(title: "Sources", paragraphs: Self.sources) }
                    NavigationLink("Privacy") { AboutPage(title: "Privacy", paragraphs: Self.privacy) }
                    VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                        Text("Road data")
                        Group {
                            if store.cache == nil && store.isLoading { Text("Loading…") }
                            else { Text(store.dataStatus) }
                            // A searched route brings its own lanes, roundabouts and lights from OpenStreetMap.
                            if !store.routeOptions.isEmpty && store.roadDataNote == nil { Text("Plus the roads along your searched route.") }
                        }
                        .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .scrollContentBackground(.hidden)
            .baxiPage()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func levelRow(_ level: ExperienceLevel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                Text(level.title)
                Text(level.summary).font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: BaxiSpace.md)
            if store.level == level { Image(systemName: "checkmark").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.accent) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(store.level == level ? [.isButton, .isSelected] : .isButton)
    }

    static let hours = [
        "Indiana requires 50 hours of supervised driving, 10 of them at night, before a new driver can get a license (IC 9-24-3-2.5).",
        "Every live drive in Baxi is logged with its start, end and miles. Replays of the practice routes are demos and never count.",
        "Baxi counts night from sunset to sunrise where the drive started. The law does not define night, so this is our reading.",
        "Export the official State Form 54706 from the Log tab. Review the entries and complete the applicable checkbox, affirmation and signatures on paper. Driver details for export are optional and saved on this device.",
    ]
    static let sources = [
        "Roads, lanes, roundabouts, lights, stop signs and speed limits: OpenStreetMap contributors (ODbL). Carmel's are built into the app; other routes download theirs when you plan them.",
        "Routes: the public OSRM route server, with Apple Maps as a backup. Weather: the National Weather Service.",
        "Crash-heavy roads and intersections: the Indianapolis MPO High Injury Network and Intersection Safety Studies. Fatal crashes: NHTSA FARS 2023, shown in Preview only.",
        "What to do at each kind of road: the Indiana Driver's Manual. How early Baxi warns you is Baxi's own design, as are the practice goals on the Log.",
    ]
    static let privacy = [
        "Baxi uses your location during a drive, and once on the Routes screen so a searched route starts where you are. Drives are saved on this phone only; there is no account.",
        "A destination search goes to Apple Maps with your location, to find places nearby. A new route sends its start (where you are) and end to the OSRM route server (or Apple, if it is down), then its path, minus the first and last 200 m, to OpenStreetMap for its road details.",
        "The weather comes from the National Weather Service for the route's start, rounded to about 1 km.",
        "During a drive nothing is sent, except to find a new route if you leave this one.",
    ]
}

private struct AboutPage: View {
    let title: String
    let paragraphs: [String]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BaxiSpace.lg) {
                ForEach(paragraphs, id: \.self) { Text($0).font(BaxiFont.body).foregroundStyle(BaxiColor.ink) }
            }
            .padding(BaxiSpace.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .baxiPage()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
