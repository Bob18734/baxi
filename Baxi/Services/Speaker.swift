import AVFoundation

/// Anything that can say a cue. The app uses Speaker; tests and the transcript tool record the lines instead.
protocol SpeechOutput: AnyObject {
    var isMuted: Bool { get set }
    func say(_ text: String)
    func stop()
}

/// Speaks one cue at a time with the system voice. Other audio (music) ducks while it talks.
final class Speaker: SpeechOutput {
    private let synth = AVSpeechSynthesizer()
    var isMuted = false

    init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt,
                                                         options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        #endif
    }

    func say(_ text: String) {
        guard !isMuted, !text.isEmpty else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        // Lines queue rather than cut each other off; a half-spoken cue is worse than a late one.
        // Off-route and arrival lines are rare and short, so the queue stays at one or two.
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}
