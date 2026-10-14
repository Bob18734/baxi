import SwiftUI
import SwiftData

/// Home: the demo drive, hours toward the 50, how much warning Baxi gives, and the voice.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Query(sort: \DriveRecord.start, order: .reverse) private var drives: [DriveRecord]

    private var totals: DriveLog.Totals { DriveLog.totals(drives.map(\.row)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BaxiSpace.xl) {
                    header
                    DemoSign { store.startDemoDrive() }
                    hours
                    WarningLevelPicker()
                    VoiceSettingsSection()
                    practiceArea
                }
                .padding(.horizontal, BaxiSpace.page)
                .padding(.bottom, BaxiSpace.xxl)
            }
            .baxiPage()
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { store.loadCarmelDemo() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.xs) {
            Text("Baxi").font(BaxiFont.hero).foregroundStyle(BaxiColor.ink)
            Text("Navigation for new drivers. It tells you what to do early, so you stay calm.")
                .font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
        }
        .padding(.top, BaxiSpace.lg)
    }

    private var hours: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            Eyebrow("Supervised hours")
            VStack(spacing: BaxiSpace.lg) {
                HStack(spacing: BaxiSpace.xxl) {
                    HoursRing(title: "Total", minutes: totals.minutes, goalMinutes: DriveLog.requiredMinutes)
                    HoursRing(title: "At night", minutes: totals.nightMinutes, goalMinutes: DriveLog.requiredNightMinutes,
                              tint: BaxiColor.route)
                }
                .frame(maxWidth: .infinity)
                Text(totals.isComplete ? "Requirement met. Print the log for the BMV."
                     : "\(DriveLog.hm(totals.minutesLeft)) to go, \(DriveLog.hm(totals.nightMinutesLeft)) of it at night.")
                    .font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                    .frame(maxWidth: .infinity)
                Text("Indiana requires 50 supervised hours, 10 of them at night (IC 9-24-3-2.5). Every live drive in Baxi counts.")
                    .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .card(padding: BaxiSpace.xl)
        }
    }

    private var practiceArea: some View {
        HStack(alignment: .top, spacing: BaxiSpace.md) {
            Image(systemName: store.cache == nil ? "map" : "checkmark.seal.fill")
                .foregroundStyle(store.cache == nil ? BaxiColor.inkFaint : BaxiColor.accent)
            VStack(alignment: .leading, spacing: BaxiSpace.xs) {
                Text("Practice area").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                Text(store.dataStatus).font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
            }
        }
        .card()
    }
}

/// The demo drive as a highway guide sign: the first thing a judge sees.
private struct DemoSign: View {
    var start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            HStack(spacing: BaxiSpace.sm) {
                Text("31").font(BaxiFont.signFace(15)).foregroundStyle(BaxiColor.signInk)
                    .frame(width: 30, height: 30)
                    .background(.white, in: Shield())
                Text("TRY IT · CARMEL").font(BaxiFont.eyebrow).tracking(1.2).opacity(0.85)
            }
            Text("Watch a demo drive").font(BaxiFont.title)
            Text("A highway merge, two exit ramps and multi-lane roundabouts, replayed in about three minutes. Replays are never logged.")
                .font(BaxiFont.callout).opacity(0.9)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: start) {
                Label("Play the demo", systemImage: "play.fill")
            }
            .buttonStyle(.baxiOnSign)
            .padding(.top, BaxiSpace.xs)
        }
        .padding(BaxiSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .signPanel(radius: BaxiRadius.xl)
    }
}

/// The US route shield outline, for the "31" on the demo sign.
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

/// How much warning Baxi gives, as three choices with what each one means.
struct WarningLevelPicker: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            Eyebrow("How much warning")
            VStack(spacing: 0) {
                ForEach(ExperienceLevel.allCases) { level in
                    Button {
                        withAnimation(.snappy) { store.level = level }
                    } label: { row(level) }
                    .buttonStyle(PressableStyle())
                    if level != ExperienceLevel.allCases.last { Divider().overlay(BaxiColor.hairline).padding(.leading, 52) }
                }
            }
            .card(padding: 0)
            Text("When each cue fires is Baxi's own design. What a cue tells you to do comes from the Indiana Driver's Manual.")
                .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
        }
    }

    private func row(_ level: ExperienceLevel) -> some View {
        let on = store.level == level
        return HStack(alignment: .top, spacing: BaxiSpace.md) {
            ZStack {
                Circle().strokeBorder(on ? BaxiColor.accent : BaxiColor.inkFaint, lineWidth: 2)
                if on { Circle().fill(BaxiColor.accent).padding(5) } // design-lint:allow the dot inside a drawn radio button
            }
            .frame(width: 22, height: 22)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: BaxiSpace.xs) {
                Text(level.title).font(BaxiFont.headline).foregroundStyle(BaxiColor.ink)
                Text(level.summary).font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(BaxiSpace.lg)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}
