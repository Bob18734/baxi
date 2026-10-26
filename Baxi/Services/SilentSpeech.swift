import Foundation

/// Used for every drive in the Mac copy, which exists only for screenshots, so it never talks aloud.
final class SilentSpeech: SpeechOutput {
    var isMuted = false
    func say(_ text: String) {}
    func stop() {}
}
