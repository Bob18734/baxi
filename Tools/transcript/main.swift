// Prints everything Baxi would say on a route, in order, with where it is said.
// A stand-in for driving it: read this to check cue wording and timing without a phone.
//
//   swift run baxi-transcript                         all presets, Getting comfortable
//   swift run baxi-transcript preset_highway new      one preset, one experience level
//   swift run baxi-transcript preset_highway new 4400 start 4400 m along, like the Home demo
//   BAXI_WHY=1 swift run baxi-transcript ...          also print the data behind each roundabout's lane advice
//   BAXI_TIME=1 swift run -c release -Xswiftc -enable-testing baxi-transcript   also time loading and cue building
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

let timing = ProcessInfo.processInfo.environment["BAXI_TIME"] != nil
func timed<T>(_ label: String, _ work: () throws -> T) rethrows -> T {
    let start = Date()
    let value = try work()
    if timing { print(String(format: "time %-28@ %7.1f ms", label as NSString, Date().timeIntervalSince(start) * 1000)) }
    return value
}

let cache = try timed("load Carmel cache") { try BundledData.carmelCache() }
let features = timed("extract features") { FeatureExtractor.extract(from: cache) }
let hin = timed("load High Injury Network") { try? BundledData.highInjuryNetwork() }

for id in presets {
    let route = try RouteService.preset(id)
    let session = timed("build cues: \(id)") { DriveSession(route: route, cache: cache, features: features, highInjury: hin, level: level,
                               mode: .replay(speedMultiplier: 1), speaker: Recorder()) }
    if let from = args.dropFirst(2).first.flatMap(Double.init) { session.skip(toMeters: from) }
    let said = session.simulateWholeRoute()
    print("\n== \(route.name) (\(id)), \(level.title): \(String(format: "%.1f", route.distanceMeters / 1609.34)) mi, \(said.count) cues, CueScheduler \(CueScheduler.isImplemented ? "student version" : "stub")")
    for e in said {
        print(String(format: "%6.2f mi  ", e.meters / 1609.34) + e.text)
    }
    if ProcessInfo.processInfo.environment["BAXI_WHY"] != nil { explainRoundabouts(route) }
}

/// For each roundabout: the mapped circle (lanes, legs), the exit, the router's lane data, and the
/// approach way's turn:lanes tag, which together decide the lane Baxi asks for.
func explainRoundabouts(_ route: PlannedRoute) {
    let tagged = cache.ways.filter { $0.turnLanes != nil && !$0.isRoundabout && !$0.coordinates.isEmpty }
    for m in route.maneuvers where m.kind == .roundabout {
        let rb = features.filter { [.singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout].contains($0.kind) }
            .min { Geo.distanceMeters($0.coordinate, m.location) < Geo.distanceMeters($1.coordinate, m.location) }
        let approach = route.polyline.coordinate(atMeters: max(0, m.alongMeters - 40))
        let way = approach.flatMap { a in tagged.min { Geo.distanceMeters(from: a, toPolyline: $0.coordinates) < Geo.distanceMeters(from: a, toPolyline: $1.coordinates) }
            .flatMap { Geo.distanceMeters(from: a, toPolyline: $0.coordinates) <= 25 ? $0 : nil } }
        print(String(format: "  why %6.2f mi", m.alongMeters / 1609.34),
              "exit \(m.exitNumber ?? 0) of \(rb?.legs ?? 0) legs, \(rb?.lanes ?? 0) lanes,",
              "router lanes \(m.laneCount.map(String.init) ?? "-") valid \(m.validLanes ?? []),",
              "turn:lanes \(way?.turnLanes ?? "-") on \(way?.name ?? "?")")
    }
}
