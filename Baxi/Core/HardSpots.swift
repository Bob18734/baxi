import Foundation

/// The spots on a route worth previewing before the drive: roundabouts, merges and ramps, turns that
/// need a lane choice on a multi-lane road, school zones and crash-heavy corridors. In route order.
struct HardSpot: Identifiable, Equatable {
    enum Kind: String { case roundabout, ramp, laneTurn, schoolZone, crashCorridor, studyIntersection, fatalCrash, glare }

    let id: String
    let kind: Kind
    let title: String
    let alongMeters: Double
    let location: Coordinate
    /// What Baxi will say about it during the drive, light counts left out. Empty when Baxi stays quiet.
    let spoken: String
    /// The road feature it matches, used to look up the students' manual briefing.
    let featureKind: FeatureKind?
    var laneStrip: LaneStrip? = nil
    var mapDataNote: String? = nil
    var context: PreviewContext? = nil
}

enum HardSpots {
    static let roundaboutMatchMeters = 80.0

    /// Fatal crashes from NHTSA FARS 2023, bundled with the app (read once).
    static let bundledFatalCrashes: [FARSCrashes.Crash] = (try? BundledData.farsCrashes().crashes) ?? []
    static let fatalMatchMeters = 75.0
    static let studyMatchMeters = 50.0

    /// FARS light-condition codes in plain words.
    static func lightPhrase(_ fars: String) -> String? {
        switch fars.lowercased() {
        case "daylight": "in daylight"
        case "dark - lighted": "after dark on a lit road"
        case "dark - not lighted": "after dark on an unlit road"
        case "dark - unknown lighting": "after dark"
        case "dawn": "at dawn"
        case "dusk": "at dusk"
        default: nil
        }
    }

    static func find(route: PlannedRoute, cues: [Cue], features: [RoadFeature],
                     fatalCrashes: [FARSCrashes.Crash] = bundledFatalCrashes,
                     studies: [IntersectionStudies.Intersection] = CueListBuilder.bundledStudies,
                     cache: OSMCache? = nil) -> [HardSpot] {
        var out: [HardSpot] = []
        let taggedRoundabouts = Set((cache?.ways ?? []).filter { $0.isRoundabout && ($0.lanes ?? 0) > 0 }.map(\.id))
        func lanes(for m: Maneuver) -> LaneStrip? {
            let mine = cues.filter { $0.maneuverId == m.id }
            return (mine.first { $0.kind == .laneChange && $0.laneStrip != nil }
                    ?? mine.first { $0.laneStrip != nil })?.laneStrip
        }
        func spoken(for m: Maneuver) -> String {
            // The lane cue is the earliest and most useful line; otherwise the maneuver's own cue.
            let mine = cues.filter { $0.maneuverId == m.id }
            let pick = mine.first { $0.kind == .laneChange } ?? mine.first { $0.kind != .signal }
            return pick?.spoken(lights: nil) ?? m.instruction
        }
        for m in route.maneuvers {
            switch m.kind {
            case .roundabout:
                let feature = features
                    .filter { [.singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout].contains($0.kind) }
                    .map { ($0, Geo.distanceMeters(m.location, $0.coordinate)) }
                    .filter { $0.1 < roundaboutMatchMeters }
                    .min { $0.1 < $1.1 }?.0
                let exit = m.exitNumber.map { ", \(CueListBuilder.ordinal($0)) exit" } ?? ""
                let tagged = feature?.osmIds.contains(where: taggedRoundabouts.contains) == true
                out.append(HardSpot(id: "m\(m.id)", kind: .roundabout, title: (tagged ? feature!.kind.label : "Roundabout") + exit,
                                    alongMeters: m.alongMeters, location: m.location, spoken: spoken(for: m),
                                    featureKind: feature?.kind,
                                    mapDataNote: tagged ? nil : "Roundabout lane count is unverified in OpenStreetMap."))
            case .merge, .onRamp, .offRamp:
                let title = m.kind == .offRamp ? "Exit ramp" : "Merge"
                out.append(HardSpot(id: "m\(m.id)", kind: .ramp, title: title + (m.roadName.map { " onto \($0)" } ?? ""),
                                    alongMeters: m.alongMeters, location: m.location, spoken: spoken(for: m),
                                    featureKind: .highwayRamp))
            case .turn, .fork:
                guard (lanes(for: m)?.laneCount ?? m.laneCount ?? 0) > 1 else { continue }
                out.append(HardSpot(id: "m\(m.id)", kind: .laneTurn, title: m.instruction,
                                    alongMeters: m.alongMeters, location: m.location, spoken: spoken(for: m),
                                    featureKind: nil))
            default: break
            }
        }
        // Preview uses the wider study radius; do not duplicate the study's spoken cue as a corridor.
        let studyPrefixes = studies.map { "study-\($0.id)-" }
        for c in cues where c.kind == .schoolZone || c.kind == .crashCorridor {
            if studyPrefixes.contains(where: c.id.hasPrefix) { continue }
            guard let loc = route.polyline.coordinate(atMeters: c.targetMeters) else { continue }
            let school = c.kind == .schoolZone
            let study = c.id.hasPrefix("study-")
            out.append(HardSpot(id: c.id, kind: school ? .schoolZone : study ? .studyIntersection : .crashCorridor, title: c.card(lights: nil),
                                alongMeters: c.targetMeters, location: loc, spoken: c.spoken(lights: nil),
                                featureKind: school ? .schoolZone : nil,
                                context: school || study ? nil : PreviewContext(source: "Indianapolis MPO High Injury Network 2026",
                                    detail: "Historical corridor counts from the bundled 2026 network, not live incident reports.",
                                    url: PreviewContext.mpoURL)))
        }
        let studyBox = GeoBox(route.polyline.points).expanded(by: studyMatchMeters)
        for study in studies {
            guard let lat = study.lat, let lon = study.lon,
                  lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else { continue }
            let at = Coordinate(lat: lat, lon: lon)
            guard studyBox.contains(at) else { continue }
            for along in route.polyline.passes(near: at, within: studyMatchMeters) {
                let spoken = cues.first { $0.id.hasPrefix("study-\(study.id)-") && abs($0.targetMeters - along) < 5 }
                out.append(HardSpot(id: "study-\(study.id)-\(Int(along))", kind: .studyIntersection,
                                    title: study.name ?? "Studied intersection", alongMeters: along, location: at,
                                    spoken: spoken?.spoken(lights: nil) ?? "", featureKind: nil,
                                    context: .study(study)))
            }
        }
        // Where a fatal crash happened on the route. Shown in the Preview only: Baxi never says it aloud,
        // because a death read out mid-drive distracts more than it helps. `spoken` is empty for these.
        let routeBox = GeoBox(route.polyline.points).expanded(by: fatalMatchMeters)
        for crash in fatalCrashes {
            guard crash.lat.isFinite, crash.lon.isFinite,
                  (-90...90).contains(crash.lat), (-180...180).contains(crash.lon) else { continue }
            let at = Coordinate(lat: crash.lat, lon: crash.lon)
            guard routeBox.contains(at) else { continue }
            for along in route.polyline.passes(near: at, within: fatalMatchMeters) {
                let when = (1...12).contains(crash.month) ? DateFormatter().monthSymbols[crash.month - 1] + " 2023" : "2023"
                out.append(HardSpot(id: "fars-\(crash.case)-\(Int(along))", kind: .fatalCrash,
                                    title: "Fatal crash record, \(when)",
                                    alongMeters: along, location: at, spoken: "", featureKind: nil, context: .fatal(crash)))
            }
        }
        for i in out.indices {
            guard let m = route.maneuvers.first(where: { "m\($0.id)" == out[i].id }) else { continue }
            out[i].laneStrip = lanes(for: m)
        }
        return out.sorted { $0.alongMeters < $1.alongMeters }
    }
}
extension HardSpots {
    /// Low-sun stretches for a drive starting at `start`, as Preview spots (they depend on the time,
    /// so they are added when the Preview opens, not with the route's other spots).
    static func glare(route: PlannedRoute, start: Date) -> [HardSpot] {
        SunGlare.stretches(route: route, start: start).compactMap { s in
            guard let at = route.polyline.coordinate(atMeters: s.startMeters) else { return nil }
            let when = start.addingTimeInterval(s.startMeters / max(1, route.polyline.lengthMeters) * route.durationSeconds)
            return HardSpot(id: "glare-\(Int(s.startMeters))", kind: .glare,
                            title: "Low sun ahead around \(when.formatted(date: .omitted, time: .shortened)) if you leave now",
                            alongMeters: s.startMeters, location: at,
                            spoken: "Low sun ahead. Traffic lights and brake lights may be hard to see", featureKind: nil)
        }
    }
}
