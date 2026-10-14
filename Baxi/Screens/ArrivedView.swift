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
                    Text(session.mode == .live ? "Drives under a minute are not logged." : "Replays are demos and never count toward the 50 hours.")
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
