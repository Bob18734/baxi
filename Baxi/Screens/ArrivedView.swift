import SwiftUI
import SwiftData

/// After a drive: what was driven, how it went (a score and at most three things to work on), any level-ups,
/// what was handled, what went into the log, and everything Baxi said. Can't be swiped away.
struct ArrivedView: View {
    let session: DriveSession
    let record: DriveRecord?
    var onDone: () -> Void
    @Query private var drives: [DriveRecord]

    private var arrived: Bool { session.progress.map { $0.remainingMeters < 300 } == true }

    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s32) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    Text(arrived ? "You made it." : "Drive ended.").role(.hero).foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(session.route.name).role(.body).foregroundStyle(Palette.meta)
                }
                if let h = session.habits { score(h) }
                stats
                if let h = session.habits { coaching(h) }
                else if session.mode == .live && session.minutes >= DriveHabits.minTrackedMinutes {
                    Text("Not enough driving on the route to judge this one.").role(.body).foregroundStyle(Palette.read)
                }
                if !levelUps.isEmpty { levelUpSection }
                if !handled.isEmpty { handledSection }
                transcript
                Text(footnote).role(.meta).foregroundStyle(Palette.meta).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s32)
            .padding(.bottom, Space.s24)
        }
        .pageBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Space.s4) {
                BigButton(title: "Done", action: onDone)
                if record != nil {
                    BigButton(title: "See it in your log", kind: .quiet) { store.tab = .log; onDone() }
                }
            }
            .padding(.horizontal, Space.margin).padding(.vertical, Space.s12)
            .background(Palette.page)
        }
        .interactiveDismissDisabled()
        .onAppear { if session.habits != nil { Haptic.reveal() } }
    }

    // MARK: The score, then the numbers

    /// The score leads: a large ring that fills once, the verdict, and what it was measured on.
    private func score(_ h: HabitReport) -> some View {
        VStack(spacing: Space.s12) {
            ZStack {
                ProgressRing(fraction: Double(h.score) / 100, size: ArrivedSize.ring, line: ArrivedSize.ringLine, animated: true)
                VStack(spacing: 0) {
                    Text("\(h.score)").role(.number).foregroundStyle(Palette.ink).monospacedDigit()
                    Text("of 100").role(.meta).foregroundStyle(Palette.meta)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Score \(h.score) out of 100")
            Text(Self.verdict(h.score)).role(.rowTitle).foregroundStyle(Palette.ink)
            Text(h.isDemo ? "A demo drive, driven the way Baxi coaches." : Self.measured(h))
                .role(.meta).foregroundStyle(Palette.meta).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var stats: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            stat(String(format: "%.1f", session.drivenMeters / 1609.34), "miles")
            if session.minutes >= 1 { stat("\(Int(session.minutes.rounded()))", "minutes") }
            // Only a drive that was logged shows what it added; the footnote says why another wasn't.
            if let record { stat(DriveLog.hm(record.dayMinutes + record.nightMinutes), record.nightMinutes > 0 ? "logged, some at night" : "logged") }
        }
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).role(.numberSmall).foregroundStyle(Palette.ink)
            Text(unit).role(.meta).foregroundStyle(Palette.meta).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Coaching

    private func coaching(_ h: HabitReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("How it went").padding(.bottom, Space.s4)
            let tips = DriveHabits.tipItems(h)
            ForEach(Array(tips.enumerated()), id: \.element.text) { i, tip in
                HStack(alignment: .top, spacing: Space.s12) {
                    Mark(glyph: Self.glyph(tip.kind), size: MarkSize.inline, weight: MarkWeight.emphasis)
                        .foregroundStyle(tip.kind == .clean ? Palette.goText : Palette.readyText)
                    VStack(alignment: .leading, spacing: Space.s4) {
                        // The school line is a reminder, not a mark-down: say so, so it can't read as a contradiction.
                        if tip.kind == .school { Text("Reminder").role(.metaStrong).foregroundStyle(Palette.readyText) }
                        Text(tip.text).role(.body).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, Space.s12)
                .accessibilityElement(children: .combine)
                if i < tips.count - 1 { Hairline() }
            }
        }
    }

    /// One line of fine print at the bottom: what the coaching is, and whether the drive counted.
    private var footnote: String {
        var parts: [String] = []
        if session.habits != nil { parts.append("Baxi's coaching, from the phone's GPS. Not a test result.") }
        if record != nil {
            let totals = DriveLog.totals(drives.map(\.row))
            parts.append("Saved to your log: \(DriveLog.hm(totals.minutes)) of 50 hours so far.")
        } else {
            parts.append(session.mode == .live ? "Drives under a minute or 200 m aren't logged." : "Replays are demos and never count toward the 50 hours.")
        }
        return parts.joined(separator: " ")
    }

    static func verdict(_ score: Int) -> String {
        switch score {
        case 95...: "Smooth and safe"
        case 80..<95: "Good drive"
        case 60..<80: "A few things to work on"
        default: "Needs practice"
        }
    }

    /// What the score is built from, so it never looks like a number from nowhere.
    static func measured(_ h: HabitReport) -> String {
        var parts = ["\(Int(h.trackedMinutes.rounded())) min on the route, speed checked where the limit is known"]
        if h.stopSigns > 0 { parts.append("\(h.stopSigns) all-way \(h.stopSigns == 1 ? "stop" : "stops")") }
        if h.merges > 0 { parts.append("\(h.merges) \(h.merges == 1 ? "merge" : "merges")") }
        return parts.joined(separator: ", ") + "."
    }

    static func glyph(_ kind: DriveHabits.Tip.Kind) -> Glyph {
        switch kind {
        case .clean: .check
        case .speed: .fastRoad
        case .stops: .stopSign
        case .braking: .brake
        case .merge: .merge
        case .school: .school
        }
    }

    // MARK: Levels and what was handled

    /// Skills that reached a new level on this drive (logged drives only).
    private var levelUps: [(skill: Skill, level: Int)] {
        guard let record else { return [] }
        let before = Practice.total(drives.filter { $0.id != record.id }.map(\.skills))
        return Practice.levelUps(before: before, after: Practice.total([before, record.skills]))
    }

    private var levelUpSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Level up").padding(.bottom, Space.s4)
            ForEach(Array(levelUps.enumerated()), id: \.element.skill) { i, up in
                Row(title: up.skill.title, detail: Practice.levelTitles[up.level], showsDivider: i < levelUps.count - 1) {
                    Mark(glyph: .skill(up.skill), size: MarkSize.standard).foregroundStyle(Palette.ink)
                } trailing: {
                    LevelSegments(level: up.level).frame(width: ArrivedSize.segments)
                }
            }
        }
    }

    private var handled: [(title: String, glyph: Glyph, count: Int)] {
        let passed = session.passedManeuvers
        return [("Roundabouts", .roundabout, passed.filter { $0.kind == .roundabout }.count),
                ("Merges and ramps", .merge, passed.filter { [.merge, .onRamp, .offRamp].contains($0.kind) }.count),
                ("Lane choices", .laneTurn, passed.filter { $0.kind == .turn && $0.needsLaneChoice }.count)]
            .filter { $0.count > 0 }
    }

    private var handledSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("You handled").padding(.bottom, Space.s4)
            ForEach(Array(handled.enumerated()), id: \.element.title) { i, item in
                Row(title: item.title, showsDivider: i < handled.count - 1) {
                    Mark(glyph: item.glyph, size: MarkSize.standard).foregroundStyle(Palette.ink)
                } trailing: {
                    Text("\(item.count)").role(.numberSmall).foregroundStyle(Palette.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: The transcript

    /// Everything Baxi said, folded away; open it to go over the drive together afterward.
    private var transcript: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(session.spokenLog.enumerated()), id: \.offset) { i, e in
                    HStack(alignment: .top, spacing: Space.s12) {
                        VStack(spacing: 0) {
                            Circle().fill(Palette.ink).frame(width: Space.s8, height: Space.s8).padding(.top, Space.s8)
                            if i < session.spokenLog.count - 1 {
                                Rectangle().fill(Palette.hairline).frame(width: Size.hairline * 2).frame(maxHeight: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: Space.s4) {
                            Text("At \(DriveView.distance(e.meters))").role(.meta).monospacedDigit().foregroundStyle(Palette.meta)
                            Text(e.text).role(.body).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, Space.s12)
                    }
                }
            }
            .padding(.top, Space.s12)
        } label: {
            Text("What Baxi said").role(.bodyStrong).foregroundStyle(Palette.ink)
        }
        .tint(Palette.ink)
    }
}
