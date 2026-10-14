import AVFoundation

/// Anything that can say a cue. The app uses Speaker; tests and the transcript tool record the lines instead.
protocol SpeechOutput: AnyObject {
    var isMuted: Bool { get set }
    func say(_ text: String)
    /// `chime`: a short tone first, for driving instructions.
    func say(_ text: String, chime: Bool)
    func stop()
}

extension SpeechOutput {
    func say(_ text: String, chime: Bool) { say(text) }
}

/// Speaks one cue at a time with the system voice. Other audio (music) ducks while it talks.
final class Speaker: NSObject, SpeechOutput, AVSpeechSynthesizerDelegate {
    static let rateKey = "voiceRate"
    private let synth = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    var isMuted = false {
        didSet { if isMuted { synth.stopSpeaking(at: .word) } }
    }

    override init() {
        voice = Self.bestVoice()
        super.init()
        synth.delegate = self
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt,
                                                         options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        #endif
    }

    /// The most natural US English voice installed: premium over enhanced over default, and among equals
    /// the voices that sound least synthetic.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let preferred = ["Ava", "Zoe", "Evan", "Nathan", "Allison", "Samantha", "Tom"]
        let us = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" && !$0.voiceTraits.contains(.isNoveltyVoice) }
        func rank(_ v: AVSpeechSynthesisVoice) -> (Int, Int) {
            (v.quality.rawValue, -(preferred.firstIndex { v.name.hasPrefix($0) } ?? preferred.count))
        }
        return us.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// "Ava (Premium)": shown in Settings, with a tip when only the basic voice is installed.
    static var voiceDescription: (name: String, isBasic: Bool) {
        guard let v = bestVoice() else { return ("System voice", true) }
        let q = v.quality == .premium ? "Premium" : v.quality == .enhanced ? "Enhanced" : "Basic"
        return ("\(v.name) (\(q))", v.quality == .default)
    }

    func say(_ text: String) { say(text, chime: false) }

    func say(_ text: String, chime: Bool) {
        guard !isMuted, !text.isEmpty else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        // Lines queue rather than cut each other off; a half-spoken cue is worse than a late one.
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        let setting = UserDefaults.standard.object(forKey: Self.rateKey) as? Double ?? 1
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.97 * Float(setting)
        u.postUtteranceDelay = 0.15
        if chime, !synth.isSpeaking {
            chimePlayer?.currentTime = 0
            chimePlayer?.play()
            u.preUtteranceDelay = 0.45   // let the tone finish before the words
        }
        synth.speak(u)
    }

    /// A soft two-note tone (G5 then C6) before an instruction, made here so there is no sound file.
    private lazy var chimePlayer: AVAudioPlayer? = {
        let rate = 44_100.0
        var samples: [Int16] = []
        for (freq, dur) in [(783.99, 0.13), (1046.5, 0.22)] {
            let n = Int(rate * dur)
            for i in 0..<n {
                let t = Double(i) / rate
                let envelope = min(1, t / 0.008) * exp(-t * 9)          // quick attack, gentle ring-out
                samples.append(Int16(sin(2 * .pi * freq * t) * envelope * 0.22 * Double(Int16.max)))
            }
        }
        var wav = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        let dataBytes = UInt32(samples.count * 2)
        wav.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + dataBytes)); wav.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(44_100)); put(UInt32(88_200)); put(UInt16(2)); put(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); put(dataBytes)
        for s in samples { put(s) }
        let p = try? AVAudioPlayer(data: wav)
        p?.volume = 0.8
        p?.prepareToPlay()
        return p
    }()

    func stop() { synth.stopSpeaking(at: .immediate) }

    // When the queue is empty, give the audio back so the driver's music comes back to full volume.
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { releaseAudioIfIdle() }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { releaseAudioIfIdle() }

    private func releaseAudioIfIdle() {
        #if os(iOS)
        guard !synth.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
