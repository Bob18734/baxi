import SwiftUI

/// First launch: what Baxi is, the safety rule, and where location goes. Shown once.
struct WelcomeView: View {
    var onDone: () -> Void
    @State private var page = 0
    @Environment(AppStore.self) private var store

    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WelcomePage(title: "Baxi rides along",
                            lines: ["Navigation for drivers with a learner's permit. It tells you early which lane to be in, how many lights until your turn, and which roundabout exit to take.",
                                    "Every drive counts toward Indiana's 50 supervised hours."]) { SampleSign() }
                    .tag(0)
                WelcomePage(title: "The driver never touches the phone",
                            lines: ["Mount the phone before you start. Indiana law bans holding a phone while driving.",
                                    "Baxi speaks each cue once. The only buttons on the Drive screen are Mute and End, for the passenger or for when you are parked.",
                                    "If Baxi and a sign or a police officer disagree, follow the sign or the officer."]) { HandsOffSign() }
                    .tag(1)
                WelcomePage(title: "Your drives stay on your phone",
                            lines: ["Baxi uses your location during a drive, to follow the route, and once on the Routes screen, so a searched route starts where you are.",
                                    "Drives are saved on this phone only. There is no account and nothing is uploaded.",
                                    "A destination search goes to Apple Maps. A new route sends its start and end points to the OSRM route server, then its path, minus the first and last 200 m, to OpenStreetMap to download the lanes, roundabouts and lights along it. The weather check sends the start, rounded to about 1 km, to the National Weather Service. Nothing is sent during the drive except to find a new route if you leave this one. The Carmel practice routes need no internet."]) { LocationMark() }
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            VStack(spacing: BaxiSpace.md) {
                HStack(spacing: BaxiSpace.sm) {
                    ForEach(0...lastPage, id: \.self) { i in
                        Capsule().fill(i == page ? BaxiColor.accent : BaxiColor.sunken)
                            .frame(width: i == page ? 24 : 8, height: 8)
                    }
                }
                .animation(.snappy, value: page)
                .accessibilityHidden(true)
                Button(page < lastPage ? "Next" : "Allow location and start") {
                    if page < lastPage { withAnimation { page += 1 } }
                    else { store.locationPermission.requestWhenInUseAuthorization(); onDone() }
                }
                .buttonStyle(.baxiPrimary)
                Button("Not now, just the demo", action: onDone)
                    .font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.accent)
                    .frame(minHeight: 44)
                    .opacity(page == lastPage ? 1 : 0)
                    .disabled(page != lastPage)
                    .accessibilityHidden(page != lastPage)
            }
            .padding(.horizontal, BaxiSpace.page)
            .padding(.bottom, BaxiSpace.md)
        }
        .baxiPage()
    }
}

private struct WelcomePage<Art: View>: View {
    let title: String
    let lines: [String]
    @ViewBuilder var art: () -> Art

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BaxiSpace.lg) {
                art().frame(maxWidth: .infinity).padding(.vertical, BaxiSpace.xl)
                Text(title).font(BaxiFont.title).foregroundStyle(BaxiColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(lines, id: \.self) {
                    Text($0).font(BaxiFont.body).foregroundStyle(BaxiColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, BaxiSpace.page + BaxiSpace.xs)
            .padding(.top, BaxiSpace.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// A small Drive-screen sign: two lanes, the right one lit, and the cue under it.
private struct SampleSign: View {
    var body: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            LaneStripView(strip: LaneStrip(laneCount: 3, highlighted: [2], labels: ["←", "↑", "↑→"]))
            HStack(spacing: BaxiSpace.md) {
                Image(systemName: "arrow.turn.up.right").font(BaxiFont.number)
                VStack(alignment: .leading, spacing: 0) {
                    Text("0.5 mi").font(BaxiFont.signFace(30))
                    Text("Right lane now, 2 lights").font(BaxiFont.headline)
                }
            }
        }
        .padding(BaxiSpace.lg)
        .frame(maxWidth: 320)
        .signPanel(radius: BaxiRadius.lg)
        .rotationEffect(.degrees(-2))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .accessibilityHidden(true)
    }
}

/// An octagon in stop-sign red: hands off the phone.
private struct HandsOffSign: View {
    var body: some View {
        ZStack {
            Octagon().fill(BaxiColor.stop)
            Octagon().inset(by: 7).stroke(.white, lineWidth: 4)
            VStack(spacing: BaxiSpace.xxs) {
                Image(systemName: "hand.raised.fill").font(BaxiFont.signFace(40))
                Text("HANDS OFF").font(BaxiFont.signFace(20))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 170, height: 170)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .accessibilityHidden(true)
    }
}

struct Octagon: InsettableShape {
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let c = r.width * 0.2929 // design-lint:allow 1 - 1/sqrt(2), the corner cut of a regular octagon
        return Path { p in
            p.move(to: CGPoint(x: r.minX + c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
            p.closeSubpath()
        }
    }
    func inset(by amount: CGFloat) -> Octagon { Octagon(inset: inset + amount) }
}

private struct LocationMark: View {
    var body: some View {
        ZStack {
            Circle().fill(BaxiColor.sunken).frame(width: 170, height: 170)
            Image(systemName: "iphone").font(BaxiFont.signFace(96, weight: "Bold")).foregroundStyle(BaxiColor.ink)
            Image(systemName: "location.fill").font(BaxiFont.signFace(30)).foregroundStyle(BaxiColor.route)
                .offset(y: -4)
        }
        .accessibilityHidden(true)
    }
}
