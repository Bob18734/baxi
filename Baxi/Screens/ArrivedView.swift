import SwiftUI
import SwiftData

/// Shown when a drive ends: what was driven, what was handled, what went into the log, and
/// everything Baxi said.
struct ArrivedView: View {
    let session: DriveSession
    let record: DriveRecord?
    var onDone: () -> Void
    @Query private var drives: [DriveRecord]

    private var handled: [(title: String, symbol: String, count: Int)] {
        let passed = session.passedManeuvers
        return [("Roundabouts", "arrow.triangle.turn.up.right.circle", passed.filter { $0.kind == .roundabout }.count),
                ("Merges and ramps", "arrow.merge", passed.filter { [.merge, .onRamp, .offRamp].contains($0.kind) }.count),
                ("Lane choices", "road.lanes", passed.filter { $0.kind == .turn && $0.needsLaneChoice }.count)]
            .filter { $0.count > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BaxiSpace.xl) {
                    banner
                    stats
                    howItWent
                    if !levelUps.isEmpty { levelUpSection }
                    if !handled.isEmpty { handledSection }
                    logSection
                    transcript
                }
                .padding(.horizontal, BaxiSpace.page)
                .padding(.vertical, BaxiSpace.lg)
            }
            .baxiPage()
            .safeAreaInset(edge: .bottom) {
                Button("Done", action: onDone).buttonStyle(.baxiPrimary)
                    .padding(.horizontal, BaxiSpace.page).padding(.vertical, BaxiSpace.sm)
                    .background(.bar)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .interactiveDismissDisabled()
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.sm) {
            Image(systemName: "flag.checkered").font(BaxiFont.title)
            Text(session.progress.map { $0.remainingMeters < 300 } == true ? "You made it" : "Drive ended")
                .font(BaxiFont.hero)
            Text(session.route.name).font(BaxiFont.headline).opacity(0.9)
        }
        .padding(BaxiSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .signPanel(radius: BaxiRadius.xl)
    }

    /// Skills that reached a new level on this drive (logged drives only).
    private var levelUps: [(skill: Skill, level: Int)] {
        guard let record else { return [] }
        let before = Practice.total(drives.filter { $0.id != record.id }.map(\.skills))
        return Practice.levelUps(before: before, after: Practice.total([before, record.skills]))
    }

    /// The habit report: a score, and up to three things to work on (or "Clean drive").
    @ViewBuilder private var howItWent: some View {
        if let h = session.habits {
            VStack(alignment: .leading, spacing: BaxiSpace.md) {
                Text("How it went").font(BaxiFont.section).foregroundStyle(BaxiColor.ink)
                HStack(alignment: .center, spacing: BaxiSpace.lg) {
                    ScoreRing(score: h.score)
                    VStack(alignment: .leading, spacing: BaxiSpace.xs) {
                        Text(Self.verdict(h.score)).font(BaxiFont.headline).foregroundStyle(BaxiColor.ink)
                        Text(h.isDemo ? "Demo drive, driven the way Baxi coaches." : Self.measured(h))
                            .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(DriveHabits.tipItems(h), id: \.text) { tip in
                    HStack(alignment: .top, spacing: BaxiSpace.md) {
                        Image(systemName: Self.symbol(tip.kind)).font(BaxiFont.headline)
                            .foregroundStyle(tip.kind == .clean ? BaxiColor.accent : BaxiColor.caution)
                            .frame(width: 28)
                        Text(tip.text).font(BaxiFont.callout).foregroundStyle(BaxiColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Baxi's coaching, from the phone's GPS. Not a test result.")
                    .font(BaxiFont.caption).foregroundStyle(BaxiColor.inkFaint)
            }
            .padding(BaxiSpace.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BaxiColor.surface, in: RoundedRectangle(cornerRadius: BaxiRadius.lg, style: .continuous))
        } else if session.mode == .live && session.minutes >= DriveHabits.minTrackedMinutes {
            Label("Not enough GPS to judge this drive.", systemImage: "location.slash")
                .font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
                .padding(.horizontal, BaxiSpace.xs)
        }
    }

    private var levelUpSection: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.sm) {
            ForEach(levelUps, id: \.skill) { up in
                HStack(spacing: BaxiSpace.md) {
                    Image(systemName: "arrow.up.circle.fill").font(BaxiFont.title).foregroundStyle(BaxiColor.accent)
                        .symbolEffect(.bounce, value: up.level)
                    VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                        Text("Level up: \(Practice.levelTitles[up.level])").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                        Text(up.skill.title).font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                    }
                    Spacer(minLength: 0)
                    LevelBar(level: up.level).frame(width: 72)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, BaxiSpace.xs)
    }

    static func verdict(_ score: Int) -> String {
        switch score {
        case 95...: "Smooth and safe"
        case 80..<95: "Good drive"
        case 60..<80: "A few things to work on"
        default: "Let's work on this together"
        }
    }

    /// What the score is built from, so it never looks like a number from nowhere.
    static func measured(_ h: HabitReport) -> String {
        var parts = ["\(Int(h.trackedMinutes.rounded())) min of driving on the route, speed checked where the limit is known"]
        if h.stopSigns > 0 { parts.append("\(h.stopSigns) all-way \(h.stopSigns == 1 ? "stop" : "stops")") }
        if h.merges > 0 { parts.append("\(h.merges) \(h.merges == 1 ? "merge" : "merges")") }
        return parts.joined(separator: ", ") + "."
    }

    static func symbol(_ kind: DriveHabits.Tip.Kind) -> String {
        switch kind {
        case .clean: "checkmark.seal.fill"
        case .speed: "gauge.with.dots.needle.67percent"
        case .stops: "hand.raised.fill"
        case .braking: "exclamationmark.triangle.fill"
        case .merge: "arrow.merge"
        case .school: "figure.walk"
        }
    }

    /// The numbers a driver cares about, on one line: how long, how far, and night time when it counts.
    private var stats: some View {
        HStack(alignment: .firstTextBaseline, spacing: BaxiSpace.xxl) {
            if session.minutes >= 1 { stat("\(Int(session.minutes.rounded()))", "min") }
            stat(String(format: "%.1f", session.drivenMeters / 1609.34), "miles")
            if let record, record.nightMinutes > 0 { stat("\(record.nightMinutes)", "min at night") }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BaxiSpace.xs)
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(BaxiFont.number).foregroundStyle(BaxiColor.ink)
            Text(unit).font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }

    private var handledSection: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            Text("You handled").font(BaxiFont.section).foregroundStyle(BaxiColor.ink)
            ForEach(handled, id: \.title) { item in
                HStack(spacing: BaxiSpace.md) {
                    Image(systemName: item.symbol).font(BaxiFont.headline).foregroundStyle(BaxiColor.onSign)
                        .frame(width: 40, height: 40).signPanel(radius: BaxiRadius.sm)
                    Text(item.title).font(BaxiFont.body).foregroundStyle(BaxiColor.ink)
                    Spacer()
                    Text("\(item.count)").font(BaxiFont.numberSmall).foregroundStyle(BaxiColor.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, BaxiSpace.xs)
    }

    /// One sentence on what this drive did for the 50 hours.
    private var logSection: some View {
        HStack(alignment: .top, spacing: BaxiSpace.md) {
            Image(systemName: record == nil ? "info.circle" : "checkmark.circle.fill")
                .font(BaxiFont.headline).foregroundStyle(record == nil ? BaxiColor.inkFaint : BaxiColor.accent)
            Group {
                if record != nil {
                    let totals = DriveLog.totals(drives.map(\.row))
                    Text("Saved to your log. \(DriveLog.hm(totals.minutes)) of 50 hours so far.")
                } else {
                    Text(session.mode == .live ? "Drives under a minute or 200 m aren't logged." : "Replays are demos and never count toward the 50 hours.")
                }
            }
            .font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
        }
        .padding(.horizontal, BaxiSpace.xs)
    }

    /// Everything Baxi said, folded away; open it to go over the drive together afterward.
    private var transcript: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(session.spokenLog.enumerated()), id: \.offset) { i, e in
                    HStack(alignment: .top, spacing: BaxiSpace.md) {
                        VStack(spacing: 0) {
                            Circle().fill(BaxiColor.accent).frame(width: 8, height: 8).padding(.top, 6)
                            if i < session.spokenLog.count - 1 {
                                Rectangle().fill(BaxiColor.hairline).frame(width: 2).frame(maxHeight: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: BaxiSpace.xxs) {
                            Text("at \(DriveView.distance(e.meters))").font(BaxiFont.caption.monospacedDigit()).foregroundStyle(BaxiColor.inkFaint)
                            Text(e.text).font(BaxiFont.callout).foregroundStyle(BaxiColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, BaxiSpace.md)
                    }
                }
            }
            .padding(.top, BaxiSpace.md)
        } label: {
            Text("What Baxi said (\(session.spokenLog.count))").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
        }
        .tint(BaxiColor.accent)
        .padding(.horizontal, BaxiSpace.xs)
    }
}
