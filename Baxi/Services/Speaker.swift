import AVFoundation

/// Speaks one cue at a time with the system voice. Other audio (music) ducks while it talks.
final class Speaker {
    private let synth = AVSpeechSynthesizer()
    var isMuted = false

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt,
                                                         options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
    }

    func say(_ text: String) {
        guard !isMuted, !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if synth.isSpeaking { synth.stopSpeaking(at: .word) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }
}
