import Foundation

/// The spots on a route worth previewing before the drive: roundabouts, merges and ramps, turns that
/// need a lane choice on a multi-lane road, school zones and crash-heavy corridors. In route order.
struct HardSpot: Identifiable, Equatable {
    enum Kind: String { case roundabout, ramp, laneTurn, schoolZone, crashCorridor }

    let id: String
    let kind: Kind
    let title: String
    let alongMeters: Double
    let location: Coordinate
    /// What Baxi will say about it during the drive, light counts left out. Empty when Baxi stays quiet.
    let spoken: String
    /// The road feature it matches, used to look up the students' manual briefing.
    let featureKind: FeatureKind?
}

enum HardSpots {
    static let roundaboutMatchMeters = 80.0

    /// Fatal crashes from NHTSA FARS 2023, bundled with the app (read once).
    static let bundledFatalCrashes: [FARSCrashes.Crash] = (try? BundledData.farsCrashes().crashes) ?? []
    static let fatalMatchMeters = 50.0

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
                     fatalCrashes: [FARSCrashes.Crash] = bundledFatalCrashes) -> [HardSpot] {
        var out: [HardSpot] = []
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
                out.append(HardSpot(id: "m\(m.id)", kind: .roundabout, title: (feature?.kind.label ?? "Roundabout") + exit,
                                    alongMeters: m.alongMeters, location: m.location, spoken: spoken(for: m),
                                    featureKind: feature?.kind ?? .singleLaneRoundabout))
            case .merge, .onRamp, .offRamp:
                let title = m.kind == .offRamp ? "Exit ramp" : "Merge"
                out.append(HardSpot(id: "m\(m.id)", kind: .ramp, title: title + (m.roadName.map { " onto \($0)" } ?? ""),
                                    alongMeters: m.alongMeters, location: m.location, spoken: spoken(for: m),
                                    featureKind: .highwayRamp))
            case .turn where (m.laneCount ?? 0) > 1:
                out.append(HardSpot(id: "m\(m.id)", kind: .laneTurn, title: m.instruction,
                                    alongMeters: m.alongMeters, location: m.location, spoken: spoken(for: m),
                                    featureKind: nil))
            default: break
            }
        }
        for c in cues where c.kind == .schoolZone || c.kind == .crashCorridor {
            guard let loc = route.polyline.coordinate(atMeters: c.targetMeters) else { continue }
            let school = c.kind == .schoolZone
            out.append(HardSpot(id: c.id, kind: school ? .schoolZone : .crashCorridor, title: c.card(lights: nil),
                                alongMeters: c.targetMeters, location: loc, spoken: c.spoken(lights: nil),
                                featureKind: school ? .schoolZone : nil))
        }
        // Where a fatal crash happened on the route. Shown in the Preview only: Baxi never says it aloud,
        // because a death read out mid-drive distracts more than it helps. `spoken` is empty for these.
        for crash in fatalCrashes {
            let at = Coordinate(lat: crash.lat, lon: crash.lon)
            for along in route.polyline.passes(near: at, within: fatalMatchMeters) {
                let when = DateFormatter().monthSymbols[max(0, min(11, crash.month - 1))]
                out.append(HardSpot(id: "fars-\(crash.case)-\(Int(along))", kind: .crashCorridor,
                                    title: "Fatal crash here, \(when) 2023" + Self.lightPhrase(crash.light).map { ", \($0)" }.orEmpty,
                                    alongMeters: along, location: at, spoken: "", featureKind: nil))
            }
        }
        return out.sorted { $0.alongMeters < $1.alongMeters }
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
