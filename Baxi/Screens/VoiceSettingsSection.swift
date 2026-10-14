import SwiftUI

/// How fast Baxi talks, with a test line. Read by Speaker each time it speaks.
struct VoiceSettingsSection: View {
    @AppStorage(Speaker.rateKey) private var rate = 1.0
    @State private var speaker: Speaker?

    var body: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Speaking speed")
                    Spacer()
                    Text(rate < 0.95 ? "Slower" : rate > 1.05 ? "Faster" : "Normal").foregroundStyle(.secondary)
                }
                Slider(value: $rate, in: 0.8...1.2, step: 0.05)
            }
            Button("Test the voice") {
                if speaker == nil { speaker = Speaker() }
                speaker?.say("Move to the right lane now for your turn, your turn is in 2 lights")
            }
        } header: { Text("Voice") } footer: {
            Text("For a clearer voice, download an Enhanced English voice in iPhone Settings, Accessibility, Spoken Content, Voices. Baxi uses the best one installed.")
        }
    }
}
