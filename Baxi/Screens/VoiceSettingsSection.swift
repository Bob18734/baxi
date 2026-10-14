import SwiftUI

/// How fast Baxi talks, with a test line. Read by Speaker each time it speaks.
struct VoiceSettingsSection: View {
    @AppStorage(Speaker.rateKey) private var rate = 1.0
    @State private var speaker: Speaker?

    var body: some View {
        VStack(alignment: .leading, spacing: BaxiSpace.md) {
            Eyebrow("Voice")
            VStack(alignment: .leading, spacing: BaxiSpace.lg) {
                HStack {
                    Text("Speaking speed").font(BaxiFont.bodyBold).foregroundStyle(BaxiColor.ink)
                    Spacer()
                    Text(rate < 0.95 ? "Slower" : rate > 1.05 ? "Faster" : "Normal")
                        .font(BaxiFont.callout).foregroundStyle(BaxiColor.inkSoft)
                }
                HStack(spacing: BaxiSpace.md) {
                    Image(systemName: "tortoise.fill").foregroundStyle(BaxiColor.inkFaint)
                    Slider(value: $rate, in: 0.8...1.2, step: 0.05)
                    Image(systemName: "hare.fill").foregroundStyle(BaxiColor.inkFaint)
                }
                Button {
                    if speaker == nil { speaker = Speaker() }
                    speaker?.say("Move to the right lane now for your turn, your turn is in 2 lights")
                } label: {
                    Label("Hear a cue", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.baxiSecondary)
            }
            .card()
            Text("For a clearer voice, download an Enhanced English voice in Settings, Accessibility, Spoken Content, Voices. Baxi uses the best one installed.")
                .font(BaxiFont.footnote).foregroundStyle(BaxiColor.inkSoft)
        }
    }
}
