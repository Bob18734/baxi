import SwiftUI
import SwiftData

/// Home answers one question, "where are you driving?": search, the Carmel practice routes, how far along the
/// 50 hours are, the skills, and the demo drive. Settings sit behind the mark at the top.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]
    @State private var showSettings = false

    private var totals: DriveLog.Totals { DriveLog.totals(drives.map(\.row)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s32) {
                VStack(alignment: .leading, spacing: Space.s16) {
                    topRow
                    Text("Where are you driving?").role(.hero).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    searchEntry
                }
                practiceRoutes
                HoursSummary(totals: totals, hasDrives: !drives.isEmpty) { store.tab = .log }
                SkillsSummary(done: Practice.total(drives.map(\.skills))) { store.tab = .log }
                BigButton(title: "Watch a 3-minute demo drive", kind: .secondary, glyph: .play, working: store.isStartingDemo) {
                    store.startDemoDrive()
                }
                .accessibilityHint("A replay of the highway loop. It's not logged.")
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.s32)
        }
        .pageBackground()
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { store.loadCarmelDemo() }
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

    private var practiceRoutes: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Practice routes in Carmel").padding(.bottom, Space.s4)
            ForEach(Array(RouteService.presets.enumerated()), id: \.element.id) { i, p in
                Button {
                    Haptic.tap()
                    store.choosePreset(p.id)
                    withAnimation(Motion.standard) { store.tab = .route }
                } label: {
                    Row(title: p.name, detail: facts(p), showsDivider: i < RouteService.presets.count - 1) {
                        RowArrow()
                    }
                }
                .buttonStyle(Press())
                .accessibilityHint("Shows the route on the map")
            }
        }
    }

    private func facts(_ p: RouteService.Preset) -> String {
        guard let m = store.presetMeters[p.id] else { return p.short }
        // Lower-case the first letter only when it starts an ordinary word ("All-way stops"), not a name ("US 31").
        let second = p.short.dropFirst().first
        let short = second?.isUppercase == true ? p.short : p.short.prefix(1).lowercased() + p.short.dropFirst()
        return "\(Int(max(1, (m / 1609.34).rounded()))) mi, \(short)"
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
                HStack(alignment: .firstTextBaseline) {
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
                    Text("No drives yet. Your first drive starts the count.").role(.meta).foregroundStyle(Palette.read)
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

/// The six skills as rings, each with its level under it. Opens the Log.
private struct SkillsSummary: View {
    let done: SkillCounts
    var open: () -> Void

    private var levels: Int { Skill.allCases.map { Practice.level($0, count: done[$0] ?? 0).level }.reduce(0, +) }

    var body: some View {
        Button { Haptic.tap(); open() } label: {
            VStack(alignment: .leading, spacing: Space.s12) {
                HStack(alignment: .firstTextBaseline) {
                    GroupLabel("Skills")
                    Spacer()
                    Text("\(levels) of \(Skill.allCases.count * 4) levels").role(.meta).foregroundStyle(Palette.meta)
                    RowArrow()
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Skill.allCases) { s in
                        VStack(spacing: Space.s8) {
                            ZStack {
                                ProgressRing(fraction: Double(done[s] ?? 0) / Double(s.goal), size: SkillRingSize.ring)
                                Mark(glyph: .skill(s), size: SkillRingSize.mark).foregroundStyle(Palette.ink)
                            }
                            Text(Practice.level(s, count: done[s] ?? 0).title).role(.meta).foregroundStyle(Palette.meta)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Skills: \(levels) of \(Skill.allCases.count * 4) levels. "
            + Skill.allCases.map { "\($0.title), \(Practice.level($0, count: done[$0] ?? 0).title)" }.joined(separator: ". "))
        .accessibilityHint("Opens the log")
    }
}
