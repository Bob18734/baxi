// Plays each demo the way the phone does, on a real-time clock: the replay timer ticks every 0.25 s at the
// demo's speed while the voice takes the real time each line lasts (the bundled recording's length, else an
// estimate). Reports every instruction that is still being said when the car reaches its maneuver, and every
// planned instruction that is never said. TIGHT: finished less than 15 m before.
//
//   swift run baxi-demo-check            the Home demo, then every preset from the start, at 4x
//   swift run baxi-demo-check 1          the same at 1x
@testable import Baxi
import AVFoundation
import Foundation

final class TimedSpeaker: SpeechOutput {
    var isMuted = false
    var now = 0.0
    var where_: () -> Double = { 0 }
    var target: () -> (Double, CueKind)? = { nil }
    private var queue: [(text: String, chime: Bool, target: (Double, CueKind)?)] = []
    private var current: (text: String, ends: Double, startM: Double, target: (Double, CueKind)?)?
    var log: [(text: String, startM: Double, endM: Double, target: (Double, CueKind)?)] = []
    var isSpeaking: Bool { current != nil || !queue.isEmpty }

    func say(_ text: String) { say(text, chime: false) }
    func say(_ text: String, chime: Bool) { queue.append((text, chime && current == nil && queue.isEmpty, target())); tick() }
    func stop() { queue.removeAll(); current = nil }

    static func seconds(_ text: String) -> Double {
        if let url = VoiceLines.recording(for: text), let p = try? AVAudioPlayer(contentsOf: url) { return p.duration }
        return CueScheduler.speechSeconds(text)
    }
    func tick() {
        if let c = current, now >= c.ends {
            log.append((c.text, c.startM, where_(), c.target)); current = nil; now += 0 // finished
        }
        if current == nil, !queue.isEmpty {
            let n = queue.removeFirst()
            current = (n.text, now + (n.chime ? 0.45 : 0) + 0.15 + Self.seconds(n.text), where_(), n.target)
        }
    }
}

let mult = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 4
let cache = try BundledData.carmelCache()
let features = FeatureExtractor.extract(from: cache)
let hin = try? BundledData.highInjuryNetwork()
// The Home demo: AppStore.demoPreset and demoStartMeters (App is not in the package).
var runs: [(String, Double?)] = [("preset_highway", 4_400)]
for p in RouteService.presets { runs.append((p.id, nil)) }
var totalLate = 0, totalMissing = 0

for (id, from) in runs {
    let route = try RouteService.preset(id)
    let sp = TimedSpeaker()
    let s = DriveSession(route: route, cache: cache, features: features, highInjury: hin, level: .gettingComfortable,
                         mode: .replay(speedMultiplier: mult), speaker: sp)
    sp.where_ = { s.progress?.alongMeters ?? from ?? 0 }
    sp.target = { s.lastCue.map { ($0.targetMeters, $0.kind) } }
    if let from { s.skip(toMeters: from) }
    s.start()   // the start line is queued; replay timer not used here
    var t = 0.0
    while !s.isFinished && t < 4 * 3600 {
        t += 0.25; sp.now = t
        s.advanceReplay(tick: 0.25, multiplier: mult)
        sp.tick()
    }
    while sp.isSpeaking { t += 0.25; sp.now = t; sp.tick() }
    print("\n== \(id)\(from.map { " from \(Int($0)) m (Home demo)" } ?? "") at \(mult)x: \(sp.log.count) lines, \(Int(t)) s")
    let instr: Set<CueKind> = [.turn, .roundabout, .ramp, .laneChange]
    for l in sp.log {
        guard let (target, kind) = l.target, instr.contains(kind), !l.text.hasPrefix("Here we go") else { continue }
        let leftAtEnd = target - l.endM
        if leftAtEnd < 15 {
            if leftAtEnd < 0 { totalLate += 1 }
            print(String(format: "\(leftAtEnd < 0 ? "LATE " : "TIGHT") %@ at %5.0f m: began %4.0f m before, finished %4.0f m %@ | %@", kind.rawValue, target,
                         target - l.startM, abs(leftAtEnd), leftAtEnd < 0 ? "AFTER" : "before", l.text))
        }
    }
    let said = Set(s.spokenLog.map { $0.meters }.map { Int($0) })
    _ = said
    let spokenIds = Set(sp.log.compactMap { $0.target.map { Int($0.0) } })
    for c in s.cues where c.fireAtMeters != nil && instr.contains(c.kind) && c.targetMeters > (from ?? 0) + 30
        && !spokenIds.contains(Int(c.targetMeters)) && !(c.kind == .laneChange) {
        totalMissing += 1
        print(String(format: "NEVER %@ at %5.0f m | %@", c.kind.rawValue, c.targetMeters, c.spokenTemplate))
    }
}
print("\nTOTAL late (finished after the maneuver) \(totalLate), never said \(totalMissing)")
