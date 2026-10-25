import SwiftUI
import SwiftData

/// Home answers one question: where are you driving? A destination search, the Carmel practice routes
/// as guide signs, and how far along the 50 hours are. Settings sit behind the gear.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]
    @State private var showSettings = false

    private var totals: DriveLog.Totals { DriveLog.totals(drives.map(\.row)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BaxiSpace.xl) {
                    header
                    whereTo
                    VStack(alignment: .leading, spacing: BaxiSpace.md) {
                        Eyebrow("Practice routes in Carmel")
                        ForEach(RouteService.presets) { p in
                            RouteSign(preset: p, miles: store.presetMeters[p.id].map { $0 / 1609.34 },
                                      skills: store.presetSkills.first { $0.id == p.id }?.skills ?? [:]) {
                                store.choosePreset(p.id)
                                store.tab = .route
                            }
                        }
                    }
                    HoursLine(totals: totals) { store.tab = .log }
                    DemoRow(starting: store.isStartingDemo) { store.startDemoDrive() }
                }
                .padding(.horizontal, BaxiSpace.page)
                .padding(.bottom, BaxiSpace.xxl)
            }
            .baxiPage()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .task { store.loadCarmelDemo() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Baxi").font(BaxiFont.hero).foregroundStyle(BaxiColor.ink)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(BaxiFont.section).foregroundStyle(BaxiColor.inkSoft)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, BaxiSpace.md)
    }

    /// Looks like a search field; opens Routes with its search active.
    private var whereTo: some View {
        Button {
            store.wantsSearch = true
            store.tab = .route
        } label: {
            HStack(spacing: BaxiSpace.md) {
                Image(systemName: "magnifyingglass").font(BaxiFont.headline).foregroundStyle(BaxiColor.inkSoft)
                Text("Where are you driving?").font(BaxiFont.body).foregroundStyle(BaxiColor.inkSoft)
                Spacer()
            }
            .padding(.horizontal, BaxiSpace.lg)
            .frame(minHeight: 54)
            .background(BaxiColor.surface, in: RoundedRectangle(cornerRadius: BaxiRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BaxiRadius.md, style: .continuous).strokeBorder(BaxiColor.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Search for a destination")
    }
}

/// A practice route as a highway guide sign: the name in sign lettering, what it practices, an arrow.
private struct RouteSign: View {
    let preset: RouteService.Preset
    let miles: Double?
    let skills: SkillCounts
    var choose: () -> Void

    private var facts: String {
        var parts: [String] = []
        if let miles { parts.append(String(format: "%.0f mi", miles)) }
        let rb = (skills[.singleLaneRoundabout] ?? 0) + (skills[.multiLaneRoundabout] ?? 0)
        if rb > 0 { parts.append("\(rb) roundabouts") }
        let ramps = (skills[.highwayMerge] ?? 0) + (skills[.exitRamp] ?? 0)
        if ramps > 0 { parts.append("\(ramps) ramps") }
        return parts.joined(separator: "   ")
    }

    var body: some View {
        Button(action: choose) {
            HStack(spacing: BaxiSpace.lg) {
                VStack(alignment: .leading, spacing: BaxiSpace.xs) {
                    Text(preset.name).font(BaxiFont.signFace(24))
                    Text(facts.isEmpty ? " " : facts).font(BaxiFont.signFace(14, weight: "Bold")).opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(BaxiFont.signFace(30))
            }
            .padding(.horizontal, BaxiSpace.xl)
            .padding(.vertical, BaxiSpace.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .signPanel(radius: BaxiRadius.lg)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(preset.name). \(facts)")
        .accessibilityHint("Opens the route on the map")
    }
}

/// Hours toward the 50 in one line, with a thin bar. Opens the Log.
private struct HoursLine: View {
    let totals: DriveLog.Totals
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: BaxiSpace.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(DriveLog.hm(totals.minutes)).font(BaxiFont.numberSmall).foregroundStyle(BaxiColor.ink)
                    Text("of 50 hours").font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
                    Spacer()
                    Text("\(DriveLog.hm(totals.nightMinutes)) of 10 at night").font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                    Image(systemName: "chevron.right").font(BaxiFont.footnote.weight(.semibold)).foregroundStyle(BaxiColor.inkFaint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(BaxiColor.sunken)
                        Capsule().fill(BaxiColor.sign)
                            .frame(width: max(6, geo.size.width * min(1, Double(totals.minutes) / Double(DriveLog.requiredMinutes))))
                            .opacity(totals.minutes == 0 ? 0 : 1)
                    }
                }
                .frame(height: 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(DriveLog.hm(totals.minutes)) of 50 supervised hours, \(DriveLog.hm(totals.nightMinutes)) of 10 at night")
        .accessibilityHint("Opens the log")
    }
}

/// For a first look (and for judges): the highway loop replayed at 4x, never logged.
private struct DemoRow: View {
    let starting: Bool
    var start: () -> Void
    var body: some View {
        Button(action: start) {
            HStack(spacing: BaxiSpace.md) {
                ZStack {
                    Image(systemName: "play.circle.fill").font(BaxiFont.title).foregroundStyle(BaxiColor.accent)
                        .opacity(starting ? 0 : 1)
                    if starting { ProgressView() }
                }
                .animation(.snappy, value: starting)
                VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                    Text("Watch a 3-minute demo drive").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                    Text("A merge, two exits and two-lane roundabouts. Not logged.").font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(starting)
        .accessibilityHint(starting ? "Starting the demo" : "Plays a demo drive. It is not logged.")
    }
}

/// The US route shield outline.
struct Shield: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX + r.width * 0.08, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.08, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.18), control: CGPoint(x: r.maxX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY * 0.85))
            p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.18), control: CGPoint(x: r.minX, y: r.maxY * 0.85))
            p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.08, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
            p.closeSubpath()
        }
    }
}
