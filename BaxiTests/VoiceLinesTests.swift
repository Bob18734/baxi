import Foundation
import Testing
@testable import Baxi

/// Oct 24: practice-route lines are pre-recorded with a natural voice. Each recording is named by the exact
/// line it says, so the app and the recording script must agree on the name.
struct VoiceLinesTests {
    @Test func keyIsStableAndMatchesTheScript() {
        // scripts/build_voice.py: hashlib.sha256(text.encode()).hexdigest()[:20]
        #expect(VoiceLines.key("You've arrived") == "b6c288c525bc4dffe57a")
        #expect(VoiceLines.key("New route") != VoiceLines.key("New route."))
    }

    @Test func everyLineInEveryPracticeDriveIsListed() throws {
        let cache = DriveSessionTests.cache, features = DriveSessionTests.features
        for p in RouteService.presets {
            let route = try RouteService.preset(p.id)
            let prep = RoutePrep.make(route: route, cache: cache, features: features, highInjury: try? BundledData.highInjuryNetwork())
            for level in ExperienceLevel.allCases {
                let listed = VoiceLines.lines(route: route, prep: prep, level: level).union(VoiceLines.fixed)
                let s = DriveSession(route: route, cache: cache, features: features, highInjury: try? BundledData.highInjuryNetwork(),
                                     level: level, mode: .replay(speedMultiplier: 1), speaker: QuietVoice(), prep: prep)
                let said = Set(s.simulateWholeRoute().map(\.text))
                #expect(said.isSubset(of: listed), "\(p.id) \(level): not listed: \(said.subtracting(listed).sorted())")
            }
        }
    }
}

extension VoiceLinesTests {
    /// A live drive with real GPS noise says its lines at slightly different points; they must still be listed.
    @Test(arguments: ["preset_firstdrive", "preset_roundabouts", "preset_parkway", "preset_highway", "preset_downtown"])
    func noisyLiveDriveLinesAreListed(_ id: String) throws {
        let cache = DriveSessionTests.cache, features = DriveSessionTests.features
        let route = try RouteService.preset(id)
        let prep = RoutePrep.make(route: route, cache: cache, features: features, highInjury: try? BundledData.highInjuryNetwork())
        let listed = VoiceLines.lines(route: route, prep: prep, level: .gettingComfortable).union(VoiceLines.fixed)
        let s = DriveSession(route: route, cache: cache, features: features, highInjury: try? BundledData.highInjuryNetwork(),
                             level: .gettingComfortable, mode: .live, speaker: QuietVoice(), prep: prep)
        let lights = CueListBuilder.signalAlongs(line: route.polyline, cache: cache)
        for f in GPSSimulator(seed: 2).fixes(for: route, lights: lights) { s.feed(f.coordinate, at: f.time) }
        let said = Set(s.spokenLog.map(\.text))
        #expect(said.isSubset(of: listed), "\(id): not listed: \(said.subtracting(listed).sorted())")
    }
}

extension VoiceLinesTests {
    /// Every line said on a practice drive has its recording in the app; an unknown line has none.
    @Test func everyListedLineHasARecording() throws {
        let cache = DriveSessionTests.cache, features = DriveSessionTests.features
        var missing: [String] = []
        for p in RouteService.presets {
            let route = try RouteService.preset(p.id)
            let prep = RoutePrep.make(route: route, cache: cache, features: features, highInjury: try? BundledData.highInjuryNetwork())
            for level in ExperienceLevel.allCases {
                missing += VoiceLines.lines(route: route, prep: prep, level: level).filter { VoiceLines.recording(for: $0) == nil }
            }
        }
        missing += VoiceLines.fixed.filter { VoiceLines.recording(for: $0) == nil }
        #expect(missing.isEmpty, "no recording for: \(Set(missing).sorted().prefix(5))")
        #expect(VoiceLines.recording(for: "In 500 feet, turn left onto Nowhere Street") == nil)
    }
}

private final class QuietVoice: SpeechOutput {
    var isMuted = false
    func say(_ text: String) {}
    func stop() {}
}
