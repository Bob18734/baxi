import AVFoundation

/// Anything that can say a cue. The app uses Speaker; tests and the transcript tool record the lines instead.
protocol SpeechOutput: AnyObject {
    var isMuted: Bool { get set }
    func say(_ text: String)
    func stop()
}

/// Speaks one cue at a time with the system voice. Other audio (music) ducks while it talks.
final class Speaker: SpeechOutput {
    static let rateKey = "voiceRate"
    private let synth = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    var isMuted = false

    init() {
        // The best US English voice installed: premium, then enhanced, then the default.
        let us = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        voice = us.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
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
        u.voice = voice
        let setting = UserDefaults.standard.object(forKey: Self.rateKey) as? Double ?? 1
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95 * Float(setting)
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}
