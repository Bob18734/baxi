import SwiftUI

/// First launch: what Baxi is, the one safety rule, and what leaves the phone. Shown once, can't be swiped away.
struct WelcomeView: View {
    var onDone: () -> Void
    @State private var page = 0
    @Environment(AppStore.self) private var store

    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WelcomeAlong(isShown: page == 0).tag(0)
                WelcomeHandsOff().tag(1)
                WelcomePrivacy().tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(Motion.standard, value: page)

            VStack(spacing: Space.s12) {
                PageDots(count: lastPage + 1, current: page)
                BigButton(title: page < lastPage ? "Next" : "Allow location and start") {
                    if page < lastPage { withAnimation(Motion.standard) { page += 1 } }
                    else { store.locationPermission.requestWhenInUseAuthorization(); Haptic.success(); onDone() }
                }
                BigButton(title: "Not now, just the demo", kind: .quiet, action: onDone)
                    .opacity(page == lastPage ? 1 : 0)
                    .disabled(page != lastPage)
                    .accessibilityHidden(page != lastPage)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.s16)
        }
        .pageBackground()
    }
}

/// Which welcome page is showing: three short bars, the current one in `go`.
private struct PageDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: Space.s8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == current ? Palette.go : Palette.track)
                    .frame(width: i == current ? Space.s24 : Space.s8, height: Space.s4)
            }
        }
        .animation(Motion.press, value: current)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// One welcome page: a mark, a headline, a few short lines, left-aligned.
private struct WelcomePage<Art: View>: View {
    let title: String
    let lines: [String]
    @ViewBuilder var art: Art
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s24) {
                art
                Text(title).role(.hero).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: Space.s12) {
                    ForEach(lines, id: \.self) { line in
                        Text(line).role(.body).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s48)
            .padding(.bottom, Space.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Page one: the signal lights red, amber, green, once (the app's one orchestrated moment); then a sample of
/// what Baxi shows while driving.
private struct WelcomeAlong: View {
    let isShown: Bool
    @State private var lit: Int? = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WelcomePage(title: "Baxi rides along.",
                    lines: ["Navigation for drivers with a learner's permit. It tells you early which lane to be in, how many lights until your turn, and which roundabout exit to take.",
                            "Every drive counts toward Indiana's 50 supervised hours."]) {
            VStack(alignment: .leading, spacing: Space.s24) {
                SignalMark(size: SignalSize.welcome, lit: lit)
                SampleCue()
            }
        }
        .task(id: isShown) {
            guard isShown else { return }
            if reduceMotion { lit = 2; return }
            lit = 0
            for step in [1, 2] {
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(Motion.standard) { lit = step }
            }
            Haptic.reveal()
        }
    }
}

/// A miniature of the Drive screen's instruction: the distance, the roundabout, the lane lit amber.
private struct SampleCue: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            HStack(alignment: .center, spacing: Space.s16) {
                RoundaboutMark(shape: RoundaboutShape(exitNumber: 2, exitAngle: 0, passedAngles: [270]), size: MarkSize.feature)
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("0.3 mi").role(.numberSmall).foregroundStyle(Palette.onDark)
                    Text("Second exit, either lane").role(.rowTitle).foregroundStyle(Palette.onDark)
                }
            }
            HStack(spacing: Space.s8) {
                ForEach(Array(["←", "↑", "↑", "→"].enumerated()), id: \.offset) { i, label in
                    let lit = i == 1 || i == 2
                    LaneMark(label: label, size: MarkSize.inline)
                        .foregroundStyle(lit ? Palette.ink : Palette.nightRead)
                        .frame(maxWidth: .infinity, minHeight: LaneSize.sample)
                        .background(lit ? Palette.ready : Palette.nightPanel, in: RoundedRectangle(cornerRadius: LaneSize.corner, style: .continuous))
                }
            }
        }
        .padding(Space.s16)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: Corner.sheet, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: in 0.3 miles, take the second exit at the roundabout, either lane.")
    }
}

private struct WelcomeHandsOff: View {
    var body: some View {
        WelcomePage(title: "The driver never touches the phone.",
                    lines: ["Mount it before you start. Indiana law bans holding a phone while driving.",
                            "Baxi says each instruction once. The only buttons while driving are Mute and End, for the passenger, or for when you're parked.",
                            "If Baxi and a sign or a police officer disagree, follow the sign or the officer."]) {
            Mark(glyph: .handsOff, size: MarkSize.feature, weight: MarkWeight.emphasis).foregroundStyle(Palette.stop)
        }
    }
}

private struct WelcomePrivacy: View {
    private let facts: [(String, String)] = [
        ("Your drives", "Saved on this phone only. There's no account, and they're never uploaded."),
        ("Your location", "Used during a drive to follow the route, and once on Routes so a searched route starts where you are."),
        ("Searching", "Goes to Apple Maps with your location, to find places nearby."),
        ("A new route", "Its start and end go to the OSRM route server (Apple if it's down). Its path, minus the first and last 200 m, goes to OpenStreetMap for the lanes, roundabouts and lights."),
        ("Weather", "The start, rounded to about 1 km, goes to the National Weather Service."),
        ("While driving", "Nothing is sent, except to find a new route if you leave this one. The Carmel practice routes need no internet."),
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s24) {
                Mark(glyph: .lock, size: MarkSize.feature, weight: MarkWeight.emphasis).foregroundStyle(Palette.ink)
                Text("Your drives stay on your phone.").role(.hero).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(facts, id: \.0) { title, text in
                        VStack(alignment: .leading, spacing: Space.s4) {
                            Text(title).role(.bodyStrong).foregroundStyle(Palette.ink)
                            Text(text).role(.meta).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, Space.s12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        Hairline()
                    }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s48)
            .padding(.bottom, Space.s24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
