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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s32) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    Text(arrived ? "You made it." : "Drive ended.").role(.hero).foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(session.route.name).role(.body).foregroundStyle(Palette.meta)
                }
                stats
                howItWent
                if !levelUps.isEmpty { levelUpSection }
                if !handled.isEmpty { handledSection }
                logLine
                transcript
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s32)
            .padding(.bottom, Space.s24)
        }
        .pageBackground()
        .safeAreaInset(edge: .bottom) {
            BigButton(title: "Done", action: onDone)
                .padding(.horizontal, Space.margin).padding(.vertical, Space.s12)
                .background(Palette.page)
        }
        .interactiveDismissDisabled()
        .onAppear { if session.habits != nil { Haptic.reveal() } }
    }

    // MARK: The numbers

    private var stats: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s32) {
            if session.minutes >= 1 { stat("\(Int(session.minutes.rounded()))", "min") }
            stat(String(format: "%.1f", session.drivenMeters / 1609.34), "miles")
            if let record, record.nightMinutes > 0 { stat("\(record.nightMinutes)", "min at night") }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).role(.number).foregroundStyle(Palette.ink)
            Text(unit).role(.meta).foregroundStyle(Palette.meta)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: How it went

    @ViewBuilder private var howItWent: some View {
        if let h = session.habits {
            VStack(alignment: .leading, spacing: Space.s16) {
                GroupLabel("How it went")
                HStack(alignment: .center, spacing: Space.s16) {
                    ZStack {
                        ProgressRing(fraction: Double(h.score) / 100, size: ArrivedSize.ring, line: ArrivedSize.ringLine, animated: true)
                        Text("\(h.score)").role(.number).foregroundStyle(Palette.ink).monospacedDigit()
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Score \(h.score) out of 100")
                    VStack(alignment: .leading, spacing: Space.s4) {
                        Text(Self.verdict(h.score)).role(.rowTitle).foregroundStyle(Palette.ink)
                        Text(h.isDemo ? "A demo drive, driven the way Baxi coaches." : Self.measured(h))
                            .role(.meta).foregroundStyle(Palette.meta).fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    let tips = DriveHabits.tipItems(h)
                    ForEach(Array(tips.enumerated()), id: \.element.text) { i, tip in
                        HStack(alignment: .top, spacing: Space.s12) {
                            Mark(glyph: Self.glyph(tip.kind), size: MarkSize.inline, weight: MarkWeight.emphasis)
                                .foregroundStyle(tip.kind == .clean ? Palette.goText : Palette.readyText)
                            Text(tip.text).role(.body).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, Space.s12)
                        .accessibilityElement(children: .combine)
                        if i < tips.count - 1 { Hairline() }
                    }
                }
                Text("Baxi's coaching, from the phone's GPS. Not a test result.").role(.meta).foregroundStyle(Palette.meta)
            }
        } else if session.mode == .live && session.minutes >= DriveHabits.minTrackedMinutes {
            Text("Not enough driving on the route to judge this one.").role(.body).foregroundStyle(Palette.read)
        }
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

    // MARK: The log and the transcript

    private var logLine: some View {
        HStack(alignment: .top, spacing: Space.s12) {
            Mark(glyph: record == nil ? .log : .check, size: MarkSize.inline, weight: MarkWeight.emphasis)
                .foregroundStyle(record == nil ? Palette.meta : Palette.goText)
            Group {
                if record != nil {
                    let totals = DriveLog.totals(drives.map(\.row))
                    Text("Saved to your log. \(DriveLog.hm(totals.minutes)) of 50 hours so far.")
                } else {
                    Text(session.mode == .live ? "Drives under a minute or 200 m aren't logged."
                                               : "Replays are demos and never count toward the 50 hours.")
                }
            }
            .role(.body).foregroundStyle(record == nil ? Palette.read : Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

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
