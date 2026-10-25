import SwiftUI

/// First launch: what Baxi is, how it works in three short pages (plan, drive, after), what leaves the phone, and a
/// setup page (experience level and hours already driven) that can be left for later. Shown once, can't be swiped
/// away.
struct WelcomeView: View {
    var onDone: () -> Void
    @State private var page = 0
    @State private var level: ExperienceLevel = .gettingComfortable
    @State private var prior = PriorHours()
    @Environment(AppStore.self) private var store

    private let setupPage = 5

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < setupPage {
                    Button("Skip") { Haptic.tap(); withAnimation(Motion.standard) { page = setupPage } }
                        .role(.bodyStrong).foregroundStyle(Palette.meta).buttonStyle(Press()).frame(minHeight: Size.tap)
                        .accessibilityHint("Goes to setup")
                }
            }
            .padding(.horizontal, Space.margin)
            .frame(minHeight: Size.tap)
            TabView(selection: $page) {
                WelcomeAlong(isShown: page == 0).tag(0)
                TutorialPlan().tag(1)
                TutorialDrive().tag(2)
                TutorialAfter(isShown: page == 3).tag(3)
                WelcomePrivacy().tag(4)
                WelcomeSetup(level: $level, prior: $prior).tag(setupPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(Motion.standard, value: page)

            VStack(spacing: Space.s8) {
                PageDots(count: setupPage + 1, current: page)
                BigButton(title: page < setupPage ? "Next" : "Save and start") {
                    if page < setupPage { withAnimation(Motion.standard) { page += 1 } }
                    else {
                        store.level = level
                        store.priorHours = prior
                        store.locationPermission.requestWhenInUseAuthorization()
                        Haptic.success()
                        onDone()
                    }
                }
                BigButton(title: "Set up later", kind: .quiet, action: onDone)
                    .opacity(page == setupPage ? 1 : 0)
                    .disabled(page != setupPage)
                    .accessibilityHidden(page != setupPage)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.s8)
        }
        .pageBackground()
        .onAppear {
            level = store.level; prior = store.priorHours
            #if DEBUG
            if let p = ScreenCheck.value("--welcome-page").flatMap(Int.init) { page = p }   // screenshots of each page
            #endif
        }
    }
}

/// Which welcome page is showing: short bars, the current one in `go`.
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

/// Page one, the app's signature moment: inside a miniature of the drive card, a signal lights red, amber, green;
/// then the instruction and the lanes appear and the distance counts down, as Baxi does on the road.
private struct WelcomeAlong: View {
    let isShown: Bool
    @State private var lit: Int? = 0
    @State private var revealed = false
    @State private var tenths = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s24) {
                SampleCue(lit: lit, revealed: revealed, tenths: tenths)
                    .padding(.top, Space.s48)
                Text("Baxi rides along.").role(.hero).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Early lane cues, light counts and roundabout exits, for drivers with a learner's permit. Every drive counts toward Indiana's 50 hours.")
                    .role(.body).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task(id: isShown) {
            guard isShown else { return }
            if reduceMotion { lit = 2; revealed = true; tenths = 3; return }
            lit = 0; revealed = false; tenths = 5
            // Stops when the page is swiped away (the task is cancelled), so nothing fires on another page.
            do {
                for step in [1, 2] {
                    try await Task.sleep(for: .milliseconds(500))
                    withAnimation(Motion.standard) { lit = step }
                }
                Haptic.reveal()
                try await Task.sleep(for: .milliseconds(250))
                withAnimation(Motion.reveal) { revealed = true }
                for t in [4, 3] {
                    try await Task.sleep(for: .milliseconds(700))
                    withAnimation(Motion.standard) { tenths = t }
                }
            } catch { return }
        }
    }
}

/// A miniature of the Drive screen's guide sign: the signal, then the distance, the roundabout and the lanes.
private struct SampleCue: View {
    let lit: Int?
    let revealed: Bool
    let tenths: Int

    var body: some View {
        GuideSign(padding: Space.s16 + SignStyle.borderInset) {
            VStack(alignment: .leading, spacing: Space.s16) {
                SignalMark(size: SignalSize.welcome, lit: lit, horizontal: true)
                VStack(alignment: .leading, spacing: Space.s12) {
                    HStack(alignment: .center, spacing: Space.s16) {
                        RoundaboutMark(shape: RoundaboutShape(exitNumber: 2, exitAngle: 0, passedAngles: [270]), size: MarkSize.feature + Space.s16,
                                       ink: Palette.onSign, way: Palette.onSign)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("0.\(tenths) mi").role(.signNumber)
                                .contentTransition(.numericText(countsDown: true))
                            Text("Second exit, either lane").role(.signLine)
                        }
                    }
                    LaneRow(strip: LaneStrip(laneCount: 4, highlighted: [1, 2], labels: ["←", "↑", "↑", "→"]), height: LaneSize.sample)
                }
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : Space.s16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: in 0.3 miles, take the second exit at the roundabout, either lane.")
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

/// A tutorial page: a working miniature of the real screen, a short headline and two lines at most.
private struct TutorialPage<Art: View>: View {
    let step: String
    let title: String
    let text: String
    @ViewBuilder var art: Art
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s24) {
                art
                    .padding(.top, Space.s24)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.s8) {
                    Text(step).role(.group).foregroundStyle(Palette.meta)
                    Text(title).role(.hero).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(text).role(.body).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct TutorialPlan: View {
    var body: some View {
        TutorialPage(step: "1 of 3", title: "Plan the drive.",
                     text: "Search anywhere, or pick a practice route. Preview the tricky spots in street view before you go.") {
            VStack(alignment: .leading, spacing: Space.s12) {
                FieldBox {
                    Mark(glyph: .search, size: MarkSize.row).foregroundStyle(Palette.meta)
                    Text("Search a destination").role(.body).foregroundStyle(Palette.meta)
                    Spacer(minLength: 0)
                }
                RouteGuideSign(name: "Downtown and the Palladium", facts: "Back-to-back roundabouts downtown, 3 mi") {}
                RouteGuideSign(name: "First drive", facts: "Quiet streets and all-way stops, 2 mi") {}
            }
        }
    }
}

private struct TutorialDrive: View {
    var body: some View {
        TutorialPage(step: "2 of 3", title: "Mount it. Hands off.",
                     text: "Baxi says each instruction once, early. Only the passenger touches the phone: Mute and End. Indiana law bans holding a phone while driving, and a sign or an officer always beats Baxi.") {
            VStack(alignment: .leading, spacing: Space.s12) {
                GuideSign(padding: Space.s16 + SignStyle.borderInset) {
                    HStack(spacing: Space.s16) {
                        Mark(glyph: .turnRight, size: MarkSize.feature, weight: MarkWeight.drive)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("0.4 mi").role(.signNumber)
                            Text("Turn right onto Main Street").role(.signLine)
                        }
                    }
                }
                HStack(spacing: Space.s12) {
                    SpeedLimitSign(mph: 30)
                    WarningSign(kind: .school, size: SignSize.height)
                    Spacer()
                    // The only two buttons in a drive, as the Drive screen draws them: the passenger's.
                    Mark(glyph: .speaker, size: MarkSize.car).foregroundStyle(Palette.ink)
                        .frame(width: DriveSize.control, height: DriveSize.control)
                        .background(Palette.field, in: Circle())
                    Text("End").role(.button).foregroundStyle(Palette.onStop)
                        .frame(width: DriveSize.endWidth, height: DriveSize.control)
                        .background(Palette.stop, in: Capsule())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("A 30 mph limit and a school zone ahead. The passenger's two buttons: Mute and End.")
            }
        }
    }
}

private struct TutorialAfter: View {
    let isShown: Bool
    var body: some View {
        TutorialPage(step: "3 of 3", title: "See how it went.",
                     text: "A score and a tip or two after every drive, skills that level up, and every drive added to your 50 hours.") {
            HStack(alignment: .center, spacing: Space.s24) {
                ZStack {
                    if isShown { ProgressRing(fraction: 0.94, size: ArrivedSize.ring * 0.75, line: ArrivedSize.ringLine, animated: true) }
                    Text("94").role(.number).foregroundStyle(Palette.ink)
                }
                .frame(width: ArrivedSize.ring * 0.75, height: ArrivedSize.ring * 0.75)
                VStack(alignment: .leading, spacing: Space.s8) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                        Text("12:40").role(.numberSmall).foregroundStyle(Palette.ink)
                        Text("of 50").role(.meta).foregroundStyle(Palette.meta)
                    }
                    ProgressLine(fraction: 0.25)
                    HStack(spacing: Space.s8) {
                        WarningSign(kind: .stop, size: MarkSize.row)
                        Text("Full stop, count to two").role(.meta).foregroundStyle(Palette.read)
                    }
                }
            }
        }
    }
}

/// Setup: how early Baxi should warn, and hours already driven. Everything can be left for later.
private struct WelcomeSetup: View {
    @Binding var level: ExperienceLevel
    @Binding var prior: PriorHours

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s24) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    Text("Set up your driving.").role(.hero).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("So Baxi warns you at the right time and counts the hours you already have. You can change both later.")
                        .role(.body).foregroundStyle(Palette.read).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    GroupLabel("Where you are now").padding(.bottom, Space.s4)
                    ForEach(Array(ExperienceLevel.allCases.enumerated()), id: \.element) { i, l in
                        Button { Haptic.tap(); withAnimation(Motion.quick) { level = l } } label: {
                            Row(title: l.title, detail: l.summary, showsDivider: i < ExperienceLevel.allCases.count - 1) {
                                Mark(glyph: .check, size: MarkSize.inline, weight: MarkWeight.emphasis).foregroundStyle(Palette.goText)
                                    .opacity(level == l ? 1 : 0)
                            }
                        }
                        .buttonStyle(Press())
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(level == l ? [.isButton, .isSelected] : .isButton)
                    }
                }
                VStack(alignment: .leading, spacing: Space.s8) {
                    GroupLabel("Hours you've already driven")
                    PriorHoursEditor(prior: $prior)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.s24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
