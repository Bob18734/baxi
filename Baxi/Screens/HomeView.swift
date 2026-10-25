import SwiftUI
import SwiftData

/// Home answers "where are you driving?" and "what should I practice next?": search, the one practice route that
/// does the most for this driver right now (the screen's main action), the hours toward 50, and the skills. The
/// full list of practice routes lives on Routes. Settings sit behind the mark at the top.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]
    @State private var showSettings = false
    @State private var showStartingPoint = false

    private var totals: DriveLog.Totals { DriveLog.totals(drives.map(\.row), prior: store.priorHours) }
    private var done: SkillCounts { Practice.total(drives.map(\.skills)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s32) {
                VStack(alignment: .leading, spacing: Space.s16) {
                    topRow
                    Text("Where are you driving?").role(.hero).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    searchEntry
                    startRow
                }
                NextDrive(suggestion: next) { preset in
                    store.choosePreset(preset.id)
                    withAnimation(Motion.standard) { store.tab = .route }
                }
                HoursSummary(totals: totals, hasDrives: !drives.isEmpty || !store.priorHours.isEmpty) { store.tab = .log }
                SkillsSummary(done: done) { store.tab = .log }
                demo
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.s32)
        }
        .pageBackground()
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showStartingPoint) { StartingPointView() }
        .task { store.loadCarmelDemo() }
    }

    /// The practice route that does the most for this driver now: First drive before any drive is logged, then
    /// the route that covers the skills furthest from their goals (Practice.suggest).
    private var next: NextDrive.Suggestion {
        let first = RouteService.presets[0]
        if drives.isEmpty {
            return .init(preset: first, reason: "Start here: quiet streets and all-way stops at 20 to 25 mph.", miles: store.presetMeters[first.id])
        }
        guard let s = Practice.suggest(done: done, routes: store.presetSkills),
              let preset = RouteService.presets.first(where: { $0.id == s.presetId }) else {
            // Every goal met, or the routes' skills are still being counted: no claim about what it practices.
            return .init(preset: first, reason: store.presetSkills.isEmpty ? nil : "Every skill goal is met. Any route keeps you sharp.",
                         miles: store.presetMeters[first.id])
        }
        // The skills furthest from their goals first, the same order the suggestion weighs them.
        let what = s.covers.sorted { Double($0.count) / Double($0.skill.goal) > Double($1.count) / Double($1.skill.goal) }
            .prefix(2).map { $0.skill.count($0.count) }.joined(separator: " and ")
        return .init(preset: preset, reason: "Practices what you need most: \(what).", miles: store.presetMeters[preset.id])
    }

    private var topRow: some View {
        HStack {
            SignalMark(size: SignalSize.corner)
            Spacer()
            MarkButton(glyph: .settings, label: "Settings") { showSettings = true }
                .padding(.trailing, -Space.s12)
        }
    }

    /// Looks like the search field; opens Routes with its search active.
    private var searchEntry: some View {
        Button {
            Haptic.tap()
            store.wantsSearch = true
            withAnimation(Motion.standard) { store.tab = .route }
        } label: {
            FieldBox {
                Mark(glyph: .search, size: MarkSize.row).foregroundStyle(Palette.meta)
                Text("Search a destination").role(.body).foregroundStyle(Palette.meta)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(Press())
        .accessibilityLabel("Search a destination")
        .accessibilityHint("Opens Routes")
    }

    /// Where a searched route starts (the phone's position unless one is chosen), and the way to change it.
    private var startRow: some View {
        Button { Haptic.tap(); showStartingPoint = true } label: {
            HStack(spacing: Space.s8) {
                Mark(glyph: .locate, size: MarkSize.tiny).foregroundStyle(Palette.meta)
                Text("From \(store.startLabel)").role(.meta).foregroundStyle(Palette.read).lineLimit(1)
                Spacer(minLength: Space.s8)
                Text("Change").role(.metaStrong).foregroundStyle(Palette.ink)
            }
            .frame(minHeight: Size.tap)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .accessibilityLabel("Searched routes start from \(store.startLabel)")
        .accessibilityHint("Choose a starting point")
    }

    /// For a first look (and for judges): a replay of the highway loop at 4x, never logged. Quiet, not a main action.
    private var demo: some View {
        Button {
            guard !store.isStartingDemo else { return }
            Haptic.tap(); store.startDemoDrive()
        } label: {
            HStack(spacing: Space.s12) {
                ZStack {
                    Mark(glyph: .play, size: MarkSize.small).opacity(store.isStartingDemo ? 0 : 1)
                    if store.isStartingDemo { SignalDots() }
                }
                .frame(minWidth: MarkSize.standard)
                Text("Watch a 3-minute demo drive").role(.bodyStrong)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.ink)
            .frame(minHeight: Size.tap)
        }
        .buttonStyle(Press())
        .accessibilityHint("A replay of the highway loop. It's not logged.")
    }
}

/// The next drive: one route, why it's the one, and the screen's main action.
private struct NextDrive: View {
    struct Suggestion { let preset: RouteService.Preset; let reason: String?; let miles: Double? }
    let suggestion: Suggestion
    let go: (RouteService.Preset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            // The screen's main action, as the guide sign it is on the road.
            RouteGuideSign(kicker: "Your next drive", name: suggestion.preset.name,
                           facts: suggestion.miles.map { "\(Int(max(1, ($0 / 1609.34).rounded()))) miles in Carmel" }, large: true) {
                go(suggestion.preset)
            }
            .accessibilityHint("Shows the route on the map")
            if let reason = suggestion.reason {
                Text(reason).role(.body).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Hours toward the 50 (10 at night): one big number, a bar, and the night line. Opens the Log.
private struct HoursSummary: View {
    let totals: DriveLog.Totals
    let hasDrives: Bool
    var open: () -> Void

    var body: some View {
        Button { Haptic.tap(); open() } label: {
            VStack(alignment: .leading, spacing: Space.s12) {
                HStack(alignment: .center) {
                    GroupLabel("Supervised hours")
                    Spacer()
                    RowArrow()
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                    Text(DriveLog.hm(totals.minutes)).role(.number).foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text("of 50").role(.body).foregroundStyle(Palette.meta)
                }
                ProgressLine(fraction: Double(totals.minutes) / Double(DriveLog.requiredMinutes))
                HStack(spacing: Space.s8) {
                    Mark(glyph: .moon, size: MarkSize.tiny).foregroundStyle(Palette.meta)
                    Text("\(DriveLog.hm(totals.nightMinutes)) of 10 at night").role(.meta).foregroundStyle(Palette.meta)
                }
                if !hasDrives {
                    Text("Your first drive starts the count.").role(.meta).foregroundStyle(Palette.read)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(DriveLog.hm(totals.minutes)) of 50 supervised hours, \(DriveLog.hm(totals.nightMinutes)) of 10 at night")
        .accessibilityHint("Opens the log")
    }
}

/// The six skills as rings you read without reading (each skill's mark inside), and the one to work on next.
private struct SkillsSummary: View {
    let done: SkillCounts
    var open: () -> Void

    /// The skill furthest from its goal.
    private var nextSkill: Skill? {
        Skill.allCases.filter { (done[$0] ?? 0) < $0.goal }
            .min { Double(done[$0] ?? 0) / Double($0.goal) < Double(done[$1] ?? 0) / Double($1.goal) }
    }

    var body: some View {
        Button { Haptic.tap(); open() } label: {
            VStack(alignment: .leading, spacing: Space.s12) {
                HStack(alignment: .center) {
                    GroupLabel("Skills")
                    Spacer()
                    if let nextSkill {
                        Text("Next: \(nextSkill.title.lowercased())").role(.meta).foregroundStyle(Palette.meta).lineLimit(1)
                    }
                    RowArrow()
                }
                HStack(spacing: 0) {
                    ForEach(Skill.allCases) { s in
                        ZStack {
                            ProgressRing(fraction: Double(done[s] ?? 0) / Double(s.goal), size: SkillRingSize.ring)
                            Mark(glyph: .skill(s), size: SkillRingSize.mark).foregroundStyle(Palette.ink)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Skills. " + Skill.allCases.map { "\($0.title), \(Practice.level($0, count: done[$0] ?? 0).title)" }.joined(separator: ". "))
        .accessibilityHint("Opens the log")
    }
}
