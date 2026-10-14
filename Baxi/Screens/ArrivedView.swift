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

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: BaxiSpace.md), GridItem(.flexible())], spacing: BaxiSpace.md) {
            stat("Time", "\(Int(session.minutes.rounded())) min")
            stat("Distance", DriveView.distance(session.drivenMeters))
            stat("Cues spoken", "\(session.spokenLog.count)")
            stat("Reroutes", "\(session.rerouteCount)")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: BaxiSpace.xs) {
            Text(value).font(BaxiFont.numberSmall).foregroundStyle(BaxiColor.ink)
            Text(label).font(BaxiFont.caption).foregroundStyle(BaxiColor.inkSoft)
        }
        .card(padding: BaxiSpace.lg)
        .accessibilityElement(children: .combine)
    }

    private var handledSection: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            Eyebrow("You handled")
            VStack(spacing: BaxiSpace.sm) {
                ForEach(handled, id: \.title) { item in
                    HStack(spacing: BaxiSpace.md) {
                        Image(systemName: item.symbol).font(BaxiFont.headline).foregroundStyle(BaxiColor.onSign)
                            .frame(width: 40, height: 40).signPanel(radius: BaxiRadius.sm)
                        Text(item.title).font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                        Spacer()
                        Text("\(item.count)").font(BaxiFont.numberSmall).foregroundStyle(BaxiColor.ink)
                    }
                }
            }
            .card()
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            Eyebrow("Saved to your log")
            VStack(alignment: .leading, spacing: BaxiSpace.sm) {
                if let record {
                    HStack(spacing: BaxiSpace.xl) {
                        VStack(alignment: .leading) {
                            Text(DriveLog.hm(record.dayMinutes)).font(BaxiFont.numberSmall)
                            Text("day").font(BaxiFont.caption).foregroundStyle(BaxiColor.inkSoft)
                        }
                        VStack(alignment: .leading) {
                            Text(DriveLog.hm(record.nightMinutes)).font(BaxiFont.numberSmall)
                            Label("night", systemImage: "moon.fill").font(BaxiFont.caption).foregroundStyle(BaxiColor.inkSoft)
                        }
                        Spacer()
                    }
                    .foregroundStyle(BaxiColor.ink)
                    let totals = DriveLog.totals(drives.map(\.row))
                    Text("\(DriveLog.hm(totals.minutes)) of 50 hours so far. Night is counted from sunset to sunrise.")
                        .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                } else {
                    Text(session.mode == .live ? "Drives under a minute are not logged."
                                               : "Replays are demos, so they never count toward the 50 hours.")
                        .font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
                }
            }
            .card()
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            Eyebrow("What Baxi said")
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
                if session.spokenLog.isEmpty {
                    Text("Nothing was said on this drive.").font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
                }
            }
            .card()
        }
    }
}
