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

/// Speaks one line at a time. A line recorded ahead of time with the natural voice (VoiceLines, the practice
/// routes) plays its recording; any other line is spoken by the best installed system voice. Lines queue
/// rather than cut each other off, a tone comes before instructions, and other audio (music) ducks while it talks.
final class Speaker: NSObject, SpeechOutput, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let rateKey = "voiceRate"
    private let synth = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private enum Line { case recording(URL), speech(AVSpeechUtterance) }
    private var queue: [(line: Line, chime: Bool)] = []
    private var playing = false
    private var player: AVAudioPlayer?
    /// Bumped by stop(), so a "line finished" from before it cannot start the next line early.
    private var generation = 0
    var isMuted = false {
        didSet { if isMuted { stop() } }
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
        let line: Line
        if let url = VoiceLines.recording(for: text) {
            line = .recording(url)
        } else {
            let u = AVSpeechUtterance(string: text)
            u.voice = voice
            let setting = UserDefaults.standard.object(forKey: Self.rateKey) as? Double ?? 1
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.97 * Float(setting)
            line = .speech(u)
        }
        // The tone only when nothing is being said: a queued line follows the one before it directly.
        queue.append((line, chime && !playing && queue.isEmpty))
        playNext()
    }

    private func playNext() {
        guard !playing, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        playing = true
        if next.chime {
            chimePlayer?.currentTime = 0
            chimePlayer?.play()
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in   // the tone first
                guard let self, self.generation == gen else { return }
                self.start(next.line)
            }
        } else {
            start(next.line)
        }
    }

    private func start(_ line: Line) {
        guard playing else { return }   // stopped while the tone played
        switch line {
        case .recording(let url):
            let rate = UserDefaults.standard.object(forKey: Self.rateKey) as? Double ?? 1
            guard let p = try? AVAudioPlayer(contentsOf: url) else { finished(); return }
            p.delegate = self
            p.enableRate = true
            p.rate = Float(min(1.5, max(0.75, rate)))
            player = p
            if !p.play() { finished() }
        case .speech(let u):
            synth.speak(u)
        }
    }

    /// One line done: a short pause, then the next, or the audio goes back to the music.
    private func finished() {
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.playing = false
            self.player = nil
            if self.queue.isEmpty { self.releaseAudioIfIdle() } else { self.playNext() }
        }
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

    func stop() {
        generation += 1
        queue.removeAll()
        player?.stop(); player = nil
        synth.stopSpeaking(at: .immediate)
        playing = false
        releaseAudioIfIdle()
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) { DispatchQueue.main.async { self.finished() } }
    func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) { DispatchQueue.main.async { self.finished() } }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { DispatchQueue.main.async { self.finished() } }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {}

    // When nothing is left to say, give the audio back so the driver's music comes back to full volume.
    private func releaseAudioIfIdle() {
        #if os(iOS)
        guard !playing, queue.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
