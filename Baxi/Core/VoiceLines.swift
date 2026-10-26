import Foundation
import CryptoKit

/// Every line Baxi can say on a practice route, so they can be recorded ahead of time with a natural voice
/// (scripts/build_voice.py, the open-source Kokoro model run on the team's Mac) and bundled. A line with no
/// recording is spoken by the iPhone's own voice, so anything missed still gets said.
enum VoiceLines {
    /// A recording's file name: the first 20 hex digits of the SHA-256 of the exact line. build_voice.py names
    /// files the same way.
    static func key(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(20).description
    }

    /// The bundled recording of `text`, if there is one. In the app the files sit at the bundle's top level;
    /// in the Mac test package they are in a Voice folder.
    static func recording(for text: String) -> URL? {
        let k = key(text)
        return Bundle.baxi.url(forResource: k, withExtension: "m4a")
            ?? Bundle.baxi.url(forResource: k, withExtension: "m4a", subdirectory: "Voice")
    }

    /// Lines said on any drive: the fixed ones, the weather at the start (without a named alert), low sun.
    static var fixed: Set<String> {
        var out = Set(DriveSession.Line.all)
        for c in RoadWeather.Condition.allCases {
            if let line = RoadWeather(summary: "", condition: c, alerts: []).spoken { out.insert(line) }
        }
        out.insert(Cue.fill(SunGlare.spokenLine, kind: .glare, lights: nil, metersAway: nil))
        return out
    }

    /// Every way each of a route's cues can be said at `level`: the distance phrase where it is normally said
    /// and the ones either side of it (a live drive fires a little early or late), every light count up to the
    /// most there can be, and the once-a-drive roundabout reminder.
    static func lines(route: PlannedRoute, prep: RoutePrep, level: ExperienceLevel) -> Set<String> {
        var out = Set<String>()
        for cue in prep.planned(for: level, route: route) {
            guard let fire = cue.fireAtMeters else { continue }
            let maneuver = cue.maneuverId.flatMap { id in route.maneuvers.first { $0.id == id } }
            let maxLights = maneuver.map {
                CueListBuilder.lightsBefore(maneuverAt: $0.alongMeters, from: max(0, fire - 300), signals: prep.signals)
            } ?? 0
            let lights: [Int?] = [nil] + Array(0...max(0, maxLights))
            for d in distances(around: cue.targetMeters - fire) {
                for l in lights {
                    let line = cue.spoken(lights: l, metersAway: d)
                    out.insert(line)
                    if cue.spokenTemplate.contains("{reminder}") { out.insert(line + DriveSession.Line.roundaboutReminder) }
                }
            }
        }
        return out
    }

    /// The distance phrase at `meters` and its neighbors, as meters values `Cue.distancePhrase` reads.
    static func distances(around meters: Double) -> [Double?] {
        let marks: [Double] = [50, 152, 305, 402, 805, 1_207, 1_609, 3_219]   // 50 m: said with no distance
        let nearest = marks.indices.min { abs(log(max(meters, 1) / marks[$0])) < abs(log(max(meters, 1) / marks[$1])) } ?? 0
        return [nil] + marks[max(0, nearest - 1)...min(marks.count - 1, nearest + 1)].map { Optional($0) }
    }
}
