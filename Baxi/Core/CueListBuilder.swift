import Foundation

/// Turns a routed trip plus the road data into the list of cues for that drive, each placed by
/// meters along the route. Built once before the drive. CueScheduler decides when each fires.
enum CueListBuilder {
    static let signalMatchMeters = 20.0
    static let stopMatchMeters = 4.0
    static let laneWayMatchMeters = 20.0
    static let speedWayMatchMeters = 15.0
    static let schoolMatchMeters = 150.0
    static let corridorMatchMeters = 30.0
    static let roundaboutMatchMeters = 80.0
    static let sampleStepMeters = 25.0
    /// A signal this close to a turn is that turn's own light.
    static let turnLightMeters = 30.0
    static let chainedTurnMeters = 60.0
    /// Two stop signs this close on the route are the two sides of one intersection; the second
    /// one faces oncoming traffic, so only the first is ours.
    static let stopPairMeters = 60.0

    static func build(route: PlannedRoute, cache: OSMCache, features: [RoadFeature],
                      highInjury: HighInjuryNetwork? = nil) -> [Cue] {
        let line = route.polyline
        guard line.lengthMeters > 0 else { return [] }
        let wayIndex = GeoIndex(ways: cache.ways.filter { $0.highway != nil && !($0.geometry ?? []).isEmpty })
        let samples = line.samples(everyMeters: sampleStepMeters)
        let laneManeuvers = route.maneuvers.filter(\.needsLaneChoice).sorted { $0.alongMeters < $1.alongMeters }
        func nextLaneManeuver(after m: Double) -> Maneuver? { laneManeuvers.first { $0.alongMeters > m } }

        var cues: [Cue] = []

        // Speed limits along the route, then changes.
        let speeds = speedProfile(samples: samples, wayIndex: wayIndex)
        func speed(at along: Double) -> Int? {
            speeds.last { $0.along <= along }?.mph ?? speeds.first?.mph
        }
        var runStart = 0, i = 1
        while i < speeds.count {
            if speeds[i].mph != speeds[runStart].mph {
                // A change counts when the new limit holds for at least 250 m (10 samples), so a short
                // advisory tag on a roundabout approach does not produce "drops to 15" then "goes up to 35".
                let runEnd = speeds[i...].firstIndex { $0.mph != speeds[i].mph } ?? speeds.count
                if runEnd - i >= 10 || runEnd == speeds.count {
                    let from = speeds[runStart].mph, to = speeds[i].mph
                    let verb = to < from ? "drops to" : "goes up to"
                    cues.append(Cue(id: "speed-\(Int(speeds[i].along))", kind: .speedChange, targetMeters: speeds[i].along,
                                    spokenTemplate: "Speed limit \(verb) \(to) in a quarter mile",
                                    cardTemplate: "Speed limit \(verb) \(to)", laneStrip: nil,
                                    roadSpeedMph: from, maneuverId: nil))
                    runStart = i
                }
                i = max(i + 1, runEnd)
            } else { i += 1 }
        }

        // Maneuvers: turns, roundabouts, ramps, lane cues, arrive. Two turns closer than
        // chainedTurnMeters become one line ("Turn left, then right away turn right"), since there is
        // no time to say the second one after the first.
        var chained: Set<Int> = []
        for (i, m) in route.maneuvers.enumerated() {
            if chained.contains(m.id) { continue }
            // The approach speed: 30 m before the maneuver, so a limit that changes at the corner does not win.
            let mph = speed(at: max(0, m.alongMeters - 30))
            switch m.kind {
            case .turn, .fork, .offRamp:
                let dir = m.direction ?? .straight
                let onto = m.roadName.map { " onto \($0)" } ?? ""
                let what: String
                switch (m.kind, dir) {
                case (.offRamp, _): what = "Take the exit on the \(dir.sideWord), slow down on the ramp, not before"
                case (_, .uturn): what = "Make a U-turn ahead"
                case (_, .straight): what = "Continue straight\(onto)"
                default: what = "Turn \(dir.spokenWord)\(onto)"
                }
                var spokenWhat = what
                if m.kind == .turn, i + 1 < route.maneuvers.count {
                    let next = route.maneuvers[i + 1]
                    if next.kind == .turn, next.alongMeters - m.alongMeters < chainedTurnMeters,
                       let nd = next.direction, nd != .straight, nd != .uturn {
                        spokenWhat += ", then right away turn \(nd.spokenWord)"
                        chained.insert(next.id)
                    }
                }
                cues.append(Cue(id: "turn-\(m.id)", kind: .turn, targetMeters: m.alongMeters,
                                spokenTemplate: spokenWhat, cardTemplate: what, laneStrip: nil, roadSpeedMph: mph, maneuverId: m.id))
                if let lane = laneCue(for: m, direction: dir, line: line, wayIndex: wayIndex, features: features, mph: mph) {
                    cues.append(lane.cue)
                }
            case .roundabout:
                let exit = m.exitNumber ?? 1
                let rb = features.filter { [.singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout].contains($0.kind) }
                    .min { Geo.distanceMeters($0.coordinate, m.location) < Geo.distanceMeters($1.coordinate, m.location) }
                let nearRb = rb.flatMap { Geo.distanceMeters($0.coordinate, m.location) <= roundaboutMatchMeters ? $0 : nil }
                let lanes = nearRb?.lanes ?? 1
                let lane = laneCue(for: m, direction: m.direction ?? .straight, line: line, wayIndex: wayIndex, features: features, mph: mph)
                var spoken = "Roundabout ahead, take the \(ordinal(exit)) exit"
                if let adviceLabel = lane?.laneLabel { spoken += ", stay in the \(adviceLabel)" }
                if lanes >= 2 { spoken += ". Pick your lane now, no lane changes inside" }
                let card = "Roundabout: \(ordinal(exit)) exit" + (lane?.laneLabel.map { ", \($0)" } ?? "")
                cues.append(Cue(id: "rb-\(m.id)", kind: .roundabout, targetMeters: m.alongMeters,
                                spokenTemplate: spoken, cardTemplate: card, laneStrip: lane?.laneStrip,
                                roadSpeedMph: mph, maneuverId: m.id))
                if let lane { cues.append(lane.cue) }
            case .merge, .onRamp:
                let text = m.kind == .onRamp
                    ? "Ramp ahead on the \((m.direction ?? .right).sideWord), speed up on the ramp to match traffic"
                    : "Merge ahead, match the speed of traffic, then merge when there is a gap"
                cues.append(Cue(id: "ramp-\(m.id)", kind: .ramp, targetMeters: m.alongMeters,
                                spokenTemplate: text, cardTemplate: m.kind == .onRamp ? "Ramp: speed up to match traffic" : "Merge: match speed, find a gap",
                                laneStrip: nil, roadSpeedMph: mph, maneuverId: m.id))
            case .arrive:
                cues.append(Cue(id: "arrive", kind: .arrive, targetMeters: m.alongMeters,
                                spokenTemplate: "You have arrived", cardTemplate: "Arrived", laneStrip: nil,
                                roadSpeedMph: mph, maneuverId: m.id))
            default: break
            }
        }
        if !cues.contains(where: { $0.kind == .arrive }) {
            cues.append(Cue(id: "arrive", kind: .arrive, targetMeters: line.lengthMeters, spokenTemplate: "You have arrived",
                            cardTemplate: "Arrived", laneStrip: nil, roadSpeedMph: nil, maneuverId: nil))
        }

        // Signals on the route. The light at a turn is the turn itself, so it gets no countdown cue,
        // but it still counts in "your turn is in N lights" (see lightsBefore).
        let stopNodes = cache.nodes.filter { $0.tags["highway"] == "stop" }
        for along in signalAlongs(line: line, cache: cache)
        where !laneManeuvers.contains(where: { abs($0.alongMeters - along) <= turnLightMeters }) {
            let next = nextLaneManeuver(after: along)
            cues.append(Cue(id: "signal-\(Int(along))", kind: .signal, targetMeters: along,
                            spokenTemplate: "{lights} to go", cardTemplate: "{lights} to your turn", laneStrip: nil,
                            roadSpeedMph: speed(at: along), maneuverId: next?.id))
        }
        for along in dedupe(onRoute(stopNodes.map(\.coordinate), line: line, within: stopMatchMeters), within: stopPairMeters) {
            cues.append(Cue(id: "stop-\(Int(along))", kind: .stopSign, targetMeters: along,
                            spokenTemplate: "Stop sign at the next street, come to a complete stop",
                            cardTemplate: "Stop sign ahead", laneStrip: nil, roadSpeedMph: speed(at: along), maneuverId: nil))
        }

        // School zones: first point where the route comes within 150 m of a school.
        for school in features.filter({ $0.kind == .schoolZone }) {
            if let s = samples.first(where: { Geo.distanceMeters($0.point, school.coordinate) <= schoolMatchMeters }) {
                let name = school.name.map { " near \($0)" } ?? ""
                cues.append(Cue(id: "school-\(school.id)", kind: .schoolZone, targetMeters: s.alongMeters,
                                spokenTemplate: "School zone ahead\(name), slow down when children are present",
                                cardTemplate: "School zone\(name)", laneStrip: nil,
                                roadSpeedMph: speed(at: s.alongMeters), maneuverId: nil))
            }
        }

        // High Injury Network corridors the route runs along.
        for seg in highInjury?.segments ?? [] {
            let polys = seg.polylines.filter { !$0.isEmpty }
            guard !polys.isEmpty else { continue }
            let hits = samples.filter { s in polys.contains { Geo.distanceMeters(from: s.point, toPolyline: $0) <= corridorMatchMeters } }
            guard let first = hits.first, let last = hits.last, hits.count >= 4 else { continue }
            let lengthM = last.alongMeters - first.alongMeters + sampleStepMeters
            let name = seg.route ?? "this road"
            let fatal = Int(seg.fatalCrashes ?? 0), serious = Int(seg.seriousInjuryCrashes ?? 0)
            cues.append(Cue(id: "hin-\(seg.id)", kind: .crashCorridor, targetMeters: first.alongMeters,
                            spokenTemplate: "Crash-heavy stretch on \(name) for the next \(milesPhrase(lengthM)), hold your speed and keep your distance",
                            cardTemplate: "\(name): \(fatal) fatal, \(serious) serious-injury crashes (MPO High Injury Network 2026)",
                            laneStrip: nil, roadSpeedMph: speed(at: first.alongMeters), maneuverId: nil))
        }

        return cues.sorted { ($0.targetMeters, $0.kind.priority) < ($1.targetMeters, $1.kind.priority) }
    }

    // MARK: Lane cues

    private static func laneCue(for m: Maneuver, direction: Maneuver.Direction, line: Polyline, wayIndex: GeoIndex,
                                features: [RoadFeature], mph: Int?) -> (laneLabel: String?, laneStrip: LaneStrip?, cue: Cue)? {
        // The approach way is the one with turn:lanes closest to a point 40 m before the maneuver.
        guard let approach = line.coordinate(atMeters: max(0, m.alongMeters - 40)) else { return nil }
        let way = wayIndex.nearest(to: approach, within: laneWayMatchMeters) { $0.turnLanes != nil && !$0.isRoundabout }
        var advice: LaneAdvice?
        var strip: LaneStrip?
        if let tl = way?.turnLanes {
            if m.kind == .roundabout {
                let rb = features.first { [.singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout].contains($0.kind)
                    && Geo.distanceMeters($0.coordinate, m.location) <= roundaboutMatchMeters }
                advice = LanePicker.pick(turnLanes: tl, exitNumber: m.exitNumber ?? 1, totalExits: rb?.legs ?? 4)
            } else {
                let dir: LanePicker.TurnDirection
                switch direction {
                case .left, .slightLeft, .sharpLeft, .uturn: dir = .left
                case .right, .slightRight, .sharpRight: dir = .right
                case .straight: dir = .through
                }
                advice = LanePicker.pickForTurn(turnLanes: tl, direction: dir)
            }
            if let advice { strip = LaneStrip(laneCount: advice.laneCount, highlighted: [advice.laneIndex], labels: laneLabels(tl)) }
        } else if let count = m.laneCount, let valid = m.validLanes, !valid.isEmpty, count > 0 {
            // The router's own lane data, when OSM has no tag.
            let idx = direction.isLeftish ? valid.min()! : valid.max()!
            let label = count == 1 ? nil : (idx == 0 ? "left lane" : idx == count - 1 ? "right lane" : "middle lane")
            if let label { advice = LaneAdvice(laneCount: count, laneIndex: idx, laneLabel: label, reason: "Router lane data") }
            strip = LaneStrip(laneCount: count, highlighted: valid, labels: Array(repeating: "", count: count))
        }
        guard let advice, advice.laneCount > 1 else { return nil }
        let what = switch m.kind {
        case .roundabout: "for the roundabout"
        case .offRamp: "for your exit"
        case .fork: "for the fork"
        default: "for your turn"
        }
        let cue = Cue(id: "lane-\(m.id)", kind: .laneChange, targetMeters: m.alongMeters,
                      spokenTemplate: "Move to the \(advice.laneLabel) now \(what){lightsClause}",
                      cardTemplate: "\(advice.laneLabel.capitalized) now{lightsClause}", laneStrip: strip,
                      roadSpeedMph: mph, maneuverId: m.id)
        return (advice.laneLabel, strip, cue)
    }

    /// Arrow labels for a turn:lanes value, left to right.
    static func laneLabels(_ turnLanes: String) -> [String] {
        turnLanes.split(separator: "|", omittingEmptySubsequences: false).map { lane in
            lane.split(separator: ";").map { tok -> String in
                switch tok {
                case "left", "sharp_left": "←"
                case "slight_left": "↖"
                case "through": "↑"
                case "right", "sharp_right": "→"
                case "slight_right": "↗"
                case "reverse": "↩"
                default: ""
                }
            }.joined()
        }
    }

    // MARK: Helpers

    /// Along-route positions of every traffic light on the route, one per intersection
    /// (OSM often maps a signal node on each approach).
    /// Posted limits along the route, one entry per 25 m sample that matches a road with a maxspeed tag.
    static func speedProfile(line: Polyline, cache: OSMCache) -> [(along: Double, mph: Int)] {
        let wayIndex = GeoIndex(ways: cache.ways.filter { $0.highway != nil && !($0.geometry ?? []).isEmpty })
        return speedProfile(samples: line.samples(everyMeters: sampleStepMeters), wayIndex: wayIndex)
    }

    private static func speedProfile(samples: [(alongMeters: Double, point: Coordinate)], wayIndex: GeoIndex) -> [(along: Double, mph: Int)] {
        samples.compactMap { s in
            wayIndex.nearest(to: s.point, within: speedWayMatchMeters) { $0.maxspeedMph != nil && !$0.isRoundabout }
                .flatMap { w in w.maxspeedMph.map { (s.alongMeters, $0) } }
        }
    }

    static func signalAlongs(line: Polyline, cache: OSMCache) -> [Double] {
        let nodes = cache.nodes.filter { $0.tags["highway"] == "traffic_signals" }.map(\.coordinate)
        return dedupe(onRoute(nodes, line: line, within: signalMatchMeters), within: 40)
    }

    /// Lights between `along` and a maneuver, counting the maneuver's own light. This is the N in
    /// "your turn is in N lights", worked out when a cue fires.
    static func lightsBefore(maneuverAt target: Double, from along: Double, signals: [Double]) -> Int {
        signals.filter { $0 > along + 5 && $0 <= target + turnLightMeters }.count
    }

    /// Along-route distances of the points that lie within `within` meters of the line.
    static func onRoute(_ points: [Coordinate], line: Polyline, within: Double) -> [Double] {
        points.compactMap { p in
            guard let proj = line.project(p), proj.crossTrackMeters <= within else { return nil }
            return proj.alongMeters
        }.sorted()
    }

    /// Collapses sorted distances closer than `within` into their first value.
    static func dedupe(_ sorted: [Double], within: Double) -> [Double] {
        var out: [Double] = []
        for d in sorted where out.last.map({ d - $0 >= within }) ?? true { out.append(d) }
        return out
    }

    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: "first"; case 2: "second"; case 3: "third"; case 4: "fourth"; case 5: "fifth"; case 6: "sixth"
        default: "\(n)th"
        }
    }

    static func milesPhrase(_ meters: Double) -> String {
        let miles = meters / 1609.34
        switch miles {
        case ..<0.35: return "quarter mile"
        case ..<0.7: return "half mile"
        case ..<1.4: return "mile"
        default: return "\(Int(miles.rounded())) miles"
        }
    }
}

private extension Maneuver.Direction {
    var isLeftish: Bool { [.left, .slightLeft, .sharpLeft, .uturn].contains(self) }
    var sideWord: String { isLeftish ? "left" : "right" }
    var spokenWord: String {
        switch self {
        case .left: "left"; case .right: "right"; case .slightLeft: "slightly left"; case .slightRight: "slightly right"
        case .sharpLeft: "sharp left"; case .sharpRight: "sharp right"; case .straight: "straight"; case .uturn: "around"
        }
    }
}

/// A grid over way geometry so "which way is nearest this point" does not scan 2,000 ways per sample.
struct GeoIndex {
    private let cell = 0.002   // about 220 m of latitude
    private var buckets: [Int: [Int]] = [:]
    private let ways: [OSMWay]

    init(ways: [OSMWay]) {
        self.ways = ways
        for (i, w) in ways.enumerated() {
            var seen = Set<Int>()
            for c in w.coordinates { let k = key(c); if seen.insert(k).inserted { buckets[k, default: []].append(i) } }
        }
    }

    private func key(_ c: Coordinate) -> Int { Int((c.lat / cell).rounded(.down)) &* 100_000 &+ Int((c.lon / cell).rounded(.down)) }

    /// Nearest way to `p` within `within` meters that passes `filter`.
    func nearest(to p: Coordinate, within: Double, where filter: (OSMWay) -> Bool) -> OSMWay? {
        var best: (OSMWay, Double)?
        var seen = Set<Int>()
        for dLat in -1...1 { for dLon in -1...1 {
            let k = key(Coordinate(lat: p.lat + Double(dLat) * cell, lon: p.lon + Double(dLon) * cell))
            for i in buckets[k] ?? [] where seen.insert(i).inserted {
                let w = ways[i]
                guard filter(w) else { continue }
                let d = Geo.distanceMeters(from: p, toPolyline: w.coordinates)
                if d <= within, best == nil || d < best!.1 { best = (w, d) }
            }
        } }
        return best?.0
    }
}
