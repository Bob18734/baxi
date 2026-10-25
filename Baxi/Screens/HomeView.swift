import SwiftUI
import SwiftData

/// Home answers one question: where are you driving? A destination search, the Carmel practice routes
/// as quiet list rows, and how far along the 50 hours are. Settings sit behind the gear.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]
    @State private var showSettings = false
    @State private var showStartingPoint = false

    private var totals: DriveLog.Totals { DriveLog.totals(drives.map(\.row)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BaxiSpace.xl) {
                    header
                    VStack(alignment: .leading, spacing: BaxiSpace.sm) {
                        Text("Plan a drive").font(BaxiFont.title).foregroundStyle(BaxiColor.ink)
                            .padding(.bottom, BaxiSpace.sm)
                        whereTo
                        Button { showStartingPoint = true } label: {
                            HStack(spacing: BaxiSpace.sm) {
                                Image(systemName: "mappin.circle.fill")
                                Text("From \(store.homeLabel)").multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                            }
                            .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                            .frame(minHeight: 44)
                        }
                        .accessibilityHint("Change the starting point for destination searches")
                    }
                    VStack(alignment: .leading, spacing: BaxiSpace.md) {
                        HStack {
                            Text("Practice routes").font(BaxiFont.headline).foregroundStyle(BaxiColor.ink)
                            Spacer()
                            Text("Carmel, IN").font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                        }
                        VStack(spacing: 0) {
                            ForEach(RouteService.presets) { p in
                                PracticeRouteRow(preset: p, miles: store.presetMeters[p.id].map { $0 / 1609.34 },
                                          skills: store.presetSkills.first { $0.id == p.id }?.skills ?? [:]) {
                                    store.choosePreset(p.id)
                                    store.tab = .route
                                }
                                if p.id != RouteService.presets.last?.id {
                                    Divider().padding(.leading, BaxiSpace.lg)
                                }
                            }
                        }
                        .background(BaxiColor.surface, in: RoundedRectangle(cornerRadius: BaxiRadius.lg))
                    }
                    VStack(alignment: .leading, spacing: BaxiSpace.md) {
                        Text("Your hours").font(BaxiFont.headline).foregroundStyle(BaxiColor.ink)
                        HoursLine(totals: totals) { store.tab = .log }
                    }
                    Divider()
                    DemoRow { store.startDemoDrive() }
                }
                .padding(.horizontal, BaxiSpace.page)
                .padding(.bottom, BaxiSpace.xxl)
            }
            .baxiPage()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showStartingPoint) { StartingPointView() }
        }
        .task { store.loadCarmelDemo() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Baxi").font(BaxiFont.section).foregroundStyle(BaxiColor.ink)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(BaxiFont.section).foregroundStyle(BaxiColor.inkSoft)
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
                Text("Search a destination").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                Spacer()
            }
            .padding(.horizontal, BaxiSpace.lg)
            .padding(.vertical, BaxiSpace.md)
            .frame(minHeight: 54)
            .background(BaxiColor.surface, in: RoundedRectangle(cornerRadius: BaxiRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BaxiRadius.md, style: .continuous).strokeBorder(BaxiColor.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Search for a destination")
    }
}

/// Consistent native rows keep practice choices secondary to destination search.
private struct PracticeRouteRow: View {
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
                Image(systemName: preset.id == "preset_roundabouts" ? "arrow.trianglehead.2.clockwise.rotate.90" : preset.id == "preset_highway" ? "arrow.merge" : "road.lanes")
                    .font(BaxiFont.headline).foregroundStyle(BaxiColor.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BaxiSpace.xs) {
                    Text(preset.name).font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                    Text(facts.isEmpty ? "Loading route details…" : facts)
                        .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(BaxiFont.caption).foregroundStyle(BaxiColor.inkFaint)
            }
            .padding(BaxiSpace.lg)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(preset.name). \(facts)")
        .accessibilityHint("Opens the route on the map")
    }
}

/// Hours with a separate night line so the summary stays readable at larger text sizes.
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
                Text("\(DriveLog.hm(totals.nightMinutes)) of 10 hours at night")
                    .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
            }
            .frame(minHeight: 44)
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
    var start: () -> Void
    var body: some View {
        Button(action: start) {
            HStack(spacing: BaxiSpace.md) {
                Image(systemName: "play.circle").font(BaxiFont.section).foregroundStyle(BaxiColor.accent)
                VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                    Text("Try a demo drive").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                    Text("3 minutes. Does not count toward your hours.").font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
        .buttonStyle(PressableStyle())
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
