// Prints everything Baxi would say on a route, in order, with where it is said.
// A stand-in for driving it: read this to check cue wording and timing without a phone.
//
//   swift run baxi-transcript                         all presets, Getting comfortable
//   swift run baxi-transcript preset_highway new      one preset, one experience level
@testable import Baxi
import Foundation

final class Recorder: SpeechOutput {
    var isMuted = false
    func say(_ text: String) {}
    func stop() {}
}

let args = Array(CommandLine.arguments.dropFirst())
let presets = args.first.map { [$0] } ?? RouteService.presets.map(\.id)
let level = args.dropFirst().first.flatMap { a in ExperienceLevel.allCases.first { $0.rawValue.lowercased().hasPrefix(a.lowercased()) } }
    ?? .gettingComfortable

let cache = try BundledData.carmelCache()
let features = FeatureExtractor.extract(from: cache)
let hin = try? BundledData.highInjuryNetwork()

for id in presets {
    let route = try RouteService.preset(id)
    let session = DriveSession(route: route, cache: cache, features: features, highInjury: hin, level: level,
                               mode: .replay(speedMultiplier: 1), speaker: Recorder())
    let said = session.simulateWholeRoute()
    print("\n== \(route.name) (\(id)), \(level.title): \(String(format: "%.1f", route.distanceMeters / 1609.34)) mi, \(said.count) cues, CueScheduler \(CueScheduler.isImplemented ? "student version" : "stub")")
    for e in said {
        print(String(format: "%6.2f mi  ", e.meters / 1609.34) + e.text)
    }
}
