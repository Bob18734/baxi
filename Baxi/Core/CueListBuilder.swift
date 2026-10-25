import Foundation

/// Turns a routed trip plus the road data into the list of cues for that drive, each placed by
/// meters along the route. Built once before the drive. CueScheduler decides when each fires.
enum CueListBuilder {
    static let signalMatchMeters = 20.0
    static let stopMatchMeters = 4.0
    static let railMatchMeters = 12.0
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

    /// The MPO's studied intersections, bundled with the app (read once).
    static let bundledStudies: [IntersectionStudies.Intersection] = (try? BundledData.intersectionStudies().intersections) ?? []
    static let studyMatchMeters = 30.0

    static func build(route: PlannedRoute, cache: OSMCache, features: [RoadFeature],
                      highInjury: HighInjuryNetwork? = nil,
                      studies: [IntersectionStudies.Intersection] = bundledStudies) -> [Cue] {
        let line = route.polyline
        guard line.lengthMeters > 0 else { return [] }
        let wayIndex = GeoIndex(ways: cache.ways.filter { $0.highway != nil && !($0.geometry ?? []).isEmpty })
        let samples = line.samples(everyMeters: sampleStepMeters)
        let laneManeuvers = route.maneuvers.filter(\.needsLaneChoice).sorted { $0.alongMeters < $1.alongMeters }
        func nextLaneManeuver(after m: Double) -> Maneuver? { laneManeuvers.first { $0.alongMeters > m } }

        var cues: [Cue] = []

        // Speed limits along the route, then changes.
        let speeds = speedProfile(samples: samples, wayIndex: wayIndex)
        func speed(at along: Double) -> Int? { Self.speed(at: along, in: speeds) }
        var runStart = 0, i = 1
        while i < speeds.count {
            if speeds[i].mph != speeds[runStart].mph {
                // A change counts when the new limit holds for at least 250 m (10 samples), so a short
                // advisory tag on a roundabout approach does not produce "drops to 15" then "goes up to 35".
                let runEnd = speeds[i...].firstIndex { $0.mph != speeds[i].mph } ?? speeds.count
                if runEnd - i >= 10 || runEnd == speeds.count {
                    let from = speeds[runStart].mph, to = speeds[i].mph
                    // Only a drop is spoken: it asks the driver to do something. A rise shows on the sign.
                    if to < from {
                        cues.append(Cue(id: "speed-\(Int(speeds[i].along))", kind: .speedChange, targetMeters: speeds[i].along,
                                        spokenTemplate: "Speed limit drops to \(to) ahead",
                                        cardTemplate: "Speed limit drops to \(to)", laneStrip: nil,
                                        roadSpeedMph: from, maneuverId: nil))
                    }
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
                case (.offRamp, _): what = "Take the exit on the \(dir.sideWord)"
                case (_, .uturn): what = "Make a U-turn"
                case (_, .straight): what = "Continue straight\(onto)"
                case (.fork, _): what = "Keep \(dir.sideWord)\(onto)"
                default: what = "Turn \(dir.spokenWord)\(onto)"
                }
                var spokenWhat = "{in}" + what.prefix(1).lowercased() + what.dropFirst()
                if m.kind == .offRamp { spokenWhat += ". Slow down once you're on the ramp" }
                if m.kind == .turn, i + 1 < route.maneuvers.count {
                    let next = route.maneuvers[i + 1]
                    if next.kind == .turn, next.alongMeters - m.alongMeters < chainedTurnMeters,
                       let nd = next.direction, nd != .straight, nd != .uturn {
                        spokenWhat += ", then an immediate \(nd.spokenWord)"
                        chained.insert(next.id)
                    }
                }
                let lane = laneCue(for: m, direction: dir, side: nil, line: line, wayIndex: wayIndex, features: features, mph: mph)
                // Said again with the turn, in case the early lane cue was too close to the last maneuver to fire.
                if let label = lane?.laneLabel, m.kind != .offRamp { spokenWhat += ". Use \(LanePicker.spoken(label))" }
                cues.append(Cue(id: "turn-\(m.id)", kind: .turn, targetMeters: m.alongMeters,
                                spokenTemplate: spokenWhat, cardTemplate: what, laneStrip: lane?.laneStrip, roadSpeedMph: mph, maneuverId: m.id))
                if let cue = lane?.cue { cues.append(cue) }
            case .roundabout where m.exitNumber == nil:
                // The router gave no exit number: say nothing it cannot back up (no exit, no lane).
                cues.append(Cue(id: "rb-\(m.id)", kind: .roundabout, targetMeters: m.alongMeters,
                                spokenTemplate: "{in}roundabout. Yield to traffic inside, then follow the map to your exit",
                                cardTemplate: "Roundabout: follow the map", laneStrip: nil, roadSpeedMph: mph, maneuverId: m.id))
            case .roundabout:
                let exit = m.exitNumber ?? 1
                let rb = roundabout(near: m, features: features)
                let lanes = rb?.lanes ?? 1
                // Which side the exit leaves on, from where the route leaves the mapped circle; the exit count
                // against the legs when the circle isn't mapped (a guessed middle can be 30-40° off).
                let side = rb.flatMap { RoundaboutDiagram.shape(for: m, route: route, center: $0.coordinate) }
                    .map { LanePicker.side(exitAngle: $0.exitAngle, exitNumber: exit) }
                    ?? LanePicker.exitSide(exitNumber: exit, totalExits: rb?.legs ?? 4)
                let lane = laneCue(for: m, direction: m.direction ?? .straight, side: side, line: line, wayIndex: wayIndex,
                                   features: features, mph: mph)
                var spoken = "{in}at the roundabout, take the \(ordinal(exit)) exit"
                if let adviceLabel = lane?.laneLabel { spoken += ". Use \(LanePicker.spoken(adviceLabel))" }
                else if lanes >= 2 { spoken += ". Either lane works" }
                // "No lane changes inside" is said at the first two-lane roundabout of a drive (DriveSession).
                if lanes >= 2 { spoken += "{reminder}" }
                let card = "Roundabout: \(ordinal(exit)) exit" + (lane?.laneLabel.map { ", \($0)" } ?? "")
                cues.append(Cue(id: "rb-\(m.id)", kind: .roundabout, targetMeters: m.alongMeters,
                                spokenTemplate: spoken, cardTemplate: card, laneStrip: lane?.laneStrip,
                                roadSpeedMph: mph, maneuverId: m.id))
                if let cue = lane?.cue { cues.append(cue) }
            case .merge, .onRamp:
                let text = m.kind == .onRamp
                    ? "{in}take the ramp on the \((m.direction ?? .right).sideWord). Speed up on it to match traffic"
                    : "{in}merge. Match the speed of traffic, then find a gap"
                cues.append(Cue(id: "ramp-\(m.id)", kind: .ramp, targetMeters: m.alongMeters,
                                spokenTemplate: text, cardTemplate: m.kind == .onRamp ? "Ramp: speed up to match traffic" : "Merge: match speed, find a gap",
                                laneStrip: nil, roadSpeedMph: mph, maneuverId: m.id))
            case .arrive:
                cues.append(Cue(id: "arrive", kind: .arrive, targetMeters: m.alongMeters,
                                spokenTemplate: "Your destination is just ahead", cardTemplate: "Destination ahead", laneStrip: nil,
                                roadSpeedMph: mph, maneuverId: m.id))
            default: break
            }
        }
        if !cues.contains(where: { $0.kind == .arrive }) {
            cues.append(Cue(id: "arrive", kind: .arrive, targetMeters: line.lengthMeters, spokenTemplate: "Your destination is just ahead",
                            cardTemplate: "Destination ahead", laneStrip: nil, roadSpeedMph: nil, maneuverId: nil))
        }

        // Signals on the route. The light at a turn is the turn itself, so it gets no countdown cue,
        // but it still counts in "your turn is in N lights" (see lightsBefore).
        let stopNodes = cache.nodes.filter { $0.tags["highway"] == "stop" && $0.tags["stop"] != "no" }
        for along in signalAlongs(line: line, cache: cache)
        where !laneManeuvers.contains(where: { abs($0.alongMeters - along) <= turnLightMeters }) {
            // Past the last turn there is nothing to count down to; the light still shows on the map.
            guard let next = nextLaneManeuver(after: along) else { continue }
            cues.append(Cue(id: "signal-\(Int(along))", kind: .signal, targetMeters: along,
                            spokenTemplate: "{lights}", cardTemplate: "{lights}", laneStrip: nil,
                            roadSpeedMph: speed(at: along), maneuverId: next.id))
        }
        // Railroad crossings (OpenStreetMap railway=level_crossing on the road).
        let crossings = cache.nodes.filter { $0.tags["railway"] == "level_crossing" }.map(\.coordinate)
        for along in dedupe(onRoute(crossings, line: line, within: railMatchMeters), within: 80) {
            cues.append(Cue(id: "rail-\(Int(along))", kind: .railroad, targetMeters: along,
                            spokenTemplate: "Railroad crossing ahead. Look and listen both ways",
                            cardTemplate: "Railroad crossing", laneStrip: nil, roadSpeedMph: speed(at: along), maneuverId: nil))
        }
        for along in dedupe(onRoute(stopNodes.map(\.coordinate), line: line, within: stopMatchMeters), within: stopPairMeters) {
            cues.append(Cue(id: "stop-\(Int(along))", kind: .stopSign, targetMeters: along,
                            spokenTemplate: "Stop sign ahead",
                            cardTemplate: "Stop sign ahead", laneStrip: nil, roadSpeedMph: speed(at: along), maneuverId: nil))
        }

        // School zones: first point where the route comes within 150 m of a school.
        for school in features.filter({ $0.kind == .schoolZone }) {
            if let s = samples.first(where: { Geo.distanceMeters($0.point, school.coordinate) <= schoolMatchMeters }) {
                let name = school.name.map { " near \($0)" } ?? ""
                cues.append(Cue(id: "school-\(school.id)", kind: .schoolZone, targetMeters: s.alongMeters,
                                spokenTemplate: "School zone ahead\(name). Slow down when kids are around",
                                cardTemplate: "School zone\(name)", laneStrip: nil,
                                roadSpeedMph: speed(at: s.alongMeters), maneuverId: nil))
            }
        }

        // High Injury Network corridors the route runs along.
        let routeBox = GeoBox(line.points).expanded(by: corridorMatchMeters)
        for seg in highInjury?.segments ?? [] {
            // Boxes first: almost every corridor in the region is nowhere near this route.
            let polys = seg.polylines.filter { !$0.isEmpty }.map { ($0, GeoBox($0).expanded(by: corridorMatchMeters)) }
                .filter { $0.1.intersects(routeBox) }
            guard !polys.isEmpty else { continue }
            let hits = samples.filter { s in polys.contains { $0.1.contains(s.point) && Geo.distanceMeters(from: s.point, toPolyline: $0.0) <= corridorMatchMeters } }
            guard let first = hits.first, let last = hits.last, hits.count >= 4 else { continue }
            let lengthM = last.alongMeters - first.alongMeters + sampleStepMeters
            let name = seg.route ?? "this road"
            let fatal = Int(seg.fatalCrashes ?? 0), serious = Int(seg.seriousInjuryCrashes ?? 0)
            cues.append(Cue(id: "hin-\(seg.id)", kind: .crashCorridor, targetMeters: first.alongMeters,
                            spokenTemplate: "The next \(milesPhrase(lengthM)) of \(name) has a lot of crashes. Keep your distance",
                            cardTemplate: "\(name): \(fatal) fatal, \(serious) serious-injury crashes (MPO High Injury Network 2026)",
                            laneStrip: nil, roadSpeedMph: speed(at: first.alongMeters), maneuverId: nil))
        }

        // Intersections the Indianapolis MPO studied for their crash history, where the route goes through one.
        for study in studies {
            guard let lat = study.lat, let lon = study.lon, let name = study.name else { continue }
            let at = Coordinate(lat: lat, lon: lon)
            guard routeBox.contains(at) else { continue }
            for along in line.passes(near: at, within: studyMatchMeters) {
                let fatal = Int(study.fatal ?? 0), serious = Int(study.incapacitating ?? 0)
                cues.append(Cue(id: "study-\(study.id)-\(Int(along))", kind: .crashCorridor, targetMeters: along,
                                spokenTemplate: "Crash-heavy intersection ahead at \(Self.spokenPlace(name)). Watch for turning cars",
                                cardTemplate: "\(name): \(fatal) fatal, \(serious) serious-injury crashes (MPO safety study)",
                                laneStrip: nil, roadSpeedMph: speed(at: along), maneuverId: nil))
            }
        }

        return cues.sorted { ($0.targetMeters, $0.kind.priority) < ($1.targetMeters, $1.kind.priority) }
    }

    // MARK: Lane cues

    /// `side`: roundabouts only, which side the exit leaves on.
    private static func laneCue(for m: Maneuver, direction: Maneuver.Direction, side: LanePicker.ExitSide?, line: Polyline,
                                wayIndex: GeoIndex, features: [RoadFeature], mph: Int?)
        -> (laneLabel: String?, laneStrip: LaneStrip?, cue: Cue?)? {
        // The approach way is the one with turn:lanes closest to a point 40 m before the maneuver.
        guard let approach = line.coordinate(atMeters: max(0, m.alongMeters - 40)) else { return nil }
        // The road the car is on, then its tag: a tagged carriageway next to it is not the car's road.
        let way = wayIndex.nearest(to: approach, within: laneWayMatchMeters) { $0.highway != nil && !$0.isRoundabout }
        let heading = line.bearing(atMeters: max(0, m.alongMeters - 40))
        var advice: LaneAdvice?
        var strip: LaneStrip?
        if let tl = way.flatMap({ w in heading.flatMap { w.turnLanes(travelling: $0, near: approach) } ?? w.turnLanes }) {
            if m.kind == .roundabout, let side {
                let options = LanePicker.throughLanes(tl)
                if side == .through, options.count > 1 {
                    // More than one lane goes straight through: show them all, ask for none.
                    return (nil, LaneStrip(laneCount: laneLabels(tl).count, highlighted: options, labels: laneLabels(tl)), nil)
                }
                advice = LanePicker.pick(turnLanes: tl, side: side, exitNumber: m.exitNumber ?? 1)
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
        } else if m.kind == .roundabout, m.laneCount == nil, let side, let rb = roundabout(near: m, features: features),
                  let tl = LanePicker.standardRoundaboutLanes(rb.lanes ?? 1) {
            // No lane data: the standard markings. Going straight either lane works: both are shown, none asked for.
            if side == .through {
                return (nil, LaneStrip(laneCount: laneLabels(tl).count, highlighted: LanePicker.throughLanes(tl), labels: laneLabels(tl)), nil)
            }
            advice = LanePicker.pick(turnLanes: tl, side: side, exitNumber: m.exitNumber ?? 1)
            if let advice { strip = LaneStrip(laneCount: advice.laneCount, highlighted: [advice.laneIndex], labels: laneLabels(tl)) }
        } else if let count = m.laneCount, let valid = m.validLanes, !valid.isEmpty, count > 0 {
            // The router's own lane data, when OSM has no tag.
            let idx = direction.isLeftish ? valid.min()! : valid.max()!
            let label = count == 1 ? nil : LanePicker.label(idx, of: count)
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
                      spokenTemplate: "Get in \(LanePicker.spoken(advice.laneLabel)) \(what){lightsClause}{ahead}",
                      cardTemplate: "\(advice.laneLabel.prefix(1).uppercased() + advice.laneLabel.dropFirst()) now{lightsClause}", laneStrip: strip,
                      roadSpeedMph: mph, maneuverId: m.id)
        return (advice.laneLabel, strip, cue)
    }

    /// The mapped roundabout this maneuver enters, if one is close enough.
    private static func roundabout(near m: Maneuver, features: [RoadFeature]) -> RoadFeature? {
        features.filter { [.singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout].contains($0.kind) }
            .min { Geo.distanceMeters($0.coordinate, m.location) < Geo.distanceMeters($1.coordinate, m.location) }
            .flatMap { Geo.distanceMeters($0.coordinate, m.location) <= roundaboutMatchMeters ? $0 : nil }
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

    /// The road the route is on decides the limit; a tagged road nearby does not lend its tag to an
    /// untagged one. Roundabout ways are skipped (their advisory limits are not the road's).
    private static func speedProfile(samples: [(alongMeters: Double, point: Coordinate)], wayIndex: GeoIndex) -> [(along: Double, mph: Int)] {
        samples.compactMap { s in
            wayIndex.nearest(to: s.point, within: speedWayMatchMeters) { !$0.isRoundabout }
                .flatMap { w in w.maxspeedMph.map { (s.alongMeters, $0) } }
        }
    }

    /// The posted limit at `along`: the last tagged sample at or before it, if no more than 50 m back
    /// (two samples). nil on untagged stretches rather than the last road's limit.
    static func speed(at along: Double, in speeds: [(along: Double, mph: Int)]) -> Int? {
        guard let s = speeds.last(where: { $0.along <= along + 1 }), along - s.along <= 2 * sampleStepMeters + 1 else { return nil }
        return s.mph
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

    /// Along-route distances of the points that lie within `within` meters of the line, once per
    /// pass, so a loop that goes through the same light twice counts it twice.
    static func onRoute(_ points: [Coordinate], line: Polyline, within: Double) -> [Double] {
        let grid = SegmentGrid(line, padMeters: within)
        let box = GeoBox(line.points).expanded(by: within)
        return points.filter(box.contains).flatMap { line.passes(near: $0, within: within, grid: grid) }.sorted()
    }

    /// Collapses sorted distances closer than `within` into their first value.
    static func dedupe(_ sorted: [Double], within: Double) -> [Double] {
        var out: [Double] = []
        for d in sorted where out.last.map({ d - $0 >= within }) ?? true { out.append(d) }
        return out
    }

    /// "146th St. at Gray Rd." as it is said: "146th Street and Gray Road".
    static func spokenPlace(_ name: String) -> String {
        var s = name.replacingOccurrences(of: " at ", with: " and ")
        for (abbr, word) in [("St.", "Street"), ("Rd.", "Road"), ("Pkwy.", "Parkway"), ("Ave.", "Avenue"), ("Blvd.", "Boulevard"),
                             ("Dr.", "Drive"), ("Ln.", "Lane"), ("Hwy.", "Highway")] {
            s = s.replacingOccurrences(of: abbr, with: word)
        }
        return s.hasSuffix(".") ? String(s.dropLast()) : s
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
