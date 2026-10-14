import SwiftUI

/// First launch: what Baxi is, the safety rules, and the location permission. Shown once.
struct WelcomeView: View {
    var onDone: () -> Void
    @State private var page = 0
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                card(symbol: "car.side.fill", title: "Baxi rides along",
                     lines: ["Navigation for new drivers with a learner's permit.",
                             "It says what to do early: which lane, how many lights until the turn, which roundabout exit and lane, where the speed limit drops.",
                             "Every drive counts toward Indiana's 50 supervised hours."]).tag(0)
                card(symbol: "hand.raised.fill", title: "The driver never touches the phone",
                     lines: ["Mount the phone before you start. Indiana law bans holding a phone while driving.",
                             "Baxi speaks each cue once. The Drive screen has nothing to tap except End and Mute, and those are for the supervising adult or for when you are parked.",
                             "If Baxi and a sign or a police officer disagree, follow the sign or the officer."]).tag(1)
                card(symbol: "location.fill", title: "Your location stays on your phone",
                     lines: ["Baxi uses your location only while a drive is on screen, to follow the route.",
                             "Drives are saved on this phone only. There is no account and nothing is uploaded.",
                             "A destination search goes to Apple Maps, and a new route is requested with just its start and end points. The Carmel practice routes need no internet."]).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 2 { withAnimation { page += 1 } }
                else { store.locationPermission.requestWhenInUseAuthorization(); onDone() }
            } label: {
                Text(page < 2 ? "Next" : "Allow location and start").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .padding()
            if page == 2 {
                Button("Not now, just the demo", action: onDone).padding(.bottom)
            }
        }
    }

    private func card(symbol: String, title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: symbol).font(.system(size: 54)).foregroundStyle(.tint)
            Text(title).font(.largeTitle.bold())
            ForEach(lines, id: \.self) { Text($0).font(.body) }
            Spacer()
        }
        .padding(28)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
