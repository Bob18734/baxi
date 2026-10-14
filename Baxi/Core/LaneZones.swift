import Foundation

/// The stretch of road where the driver should move into the right lane for a turn or roundabout, so it
/// can be drawn on the map, not only spoken. It starts where Baxi says the lane cue (the same timing, so
/// the voice and the map agree) and ends where the driver must already be in the lane: before the solid
/// lane lines near the intersection, and before a roundabout's entry, where lane changes are not allowed.
struct LaneZone: Identifiable, Equatable {
    enum Side: Equatable { case left, right, middle }

    let id: String
    let maneuverId: Int
    /// Start changing lanes from here.
    let startMeters: Double
    /// Be in the lane by here.
    let endMeters: Double
    /// The turn or roundabout itself.
    let maneuverMeters: Double
    let strip: LaneStrip
    /// "right lane", when one lane is the answer; nil when several are.
    let laneLabel: String?
    /// Which side of the road the lane is on, for the arrow the driver sees.
    let side: Side
    let isRoundabout: Bool

    /// The words for the zone: "Move to the right lane", "Move to lanes 2 or 3".
    var instruction: String {
        if let laneLabel { return "Move to \(LanePicker.spoken(laneLabel))" }
        let lanes = strip.highlighted.sorted().map { String($0 + 1) }
        return lanes.count > 1 ? "Move to lane \(lanes.dropLast().joined(separator: ", ")) or \(lanes.last!)" : "Pick your lane"
    }
}

enum LaneZones {
    /// Be in the lane this far before a roundabout's entry or a turn: lane lines usually turn solid near
    /// an intersection, and Baxi already tells drivers not to change lanes inside a roundabout.
    static let roundaboutCommitMeters = 30.0
    static let turnCommitMeters = 40.0
    /// A zone shorter than this is drawn this long anyway, so it is visible and actionable.
    static let minimumMeters = 60.0
    /// Before the cue fires there is nothing on screen; the zone counts as active from a little before.
    static let leadInMeters = 30.0

    /// One zone per maneuver whose lanes are known and where not every lane works. `cues` are the planned
    /// cues (fireAtMeters set for the driver's level).
    static func build(cues: [Cue], route: PlannedRoute) -> [LaneZone] {
        let maneuvers = route.maneuvers.filter(\.needsLaneChoice).sorted { $0.alongMeters < $1.alongMeters }
        let boundaries = RoutePrep.boundaries(route)
        var out: [LaneZone] = []
        for m in maneuvers {
            let mine = cues.filter { $0.maneuverId == m.id }
            let lane = mine.first { $0.kind == .laneChange }
            let main = mine.first { $0.kind == .turn || $0.kind == .roundabout }
            guard let strip = lane?.laneStrip ?? main?.laneStrip, strip.laneCount >= 2,
                  !strip.highlighted.isEmpty, strip.highlighted.count < strip.laneCount else { continue }
            let roundabout = m.kind == .roundabout
            let end = max(0, m.alongMeters - (roundabout ? roundaboutCommitMeters : turnCommitMeters))
            let fires = [lane?.fireAtMeters, main?.fireAtMeters].compactMap { $0 }
            var start = fires.min() ?? (m.alongMeters - 300)
            start = min(start, end - minimumMeters)
            // Not before the last maneuver (a merge counts) is done: the driver is still finishing that one.
            if let previous = boundaries.last(where: { $0 < m.alongMeters - 1 }) { start = max(start, previous + 15) }
            start = max(0, min(start, end - 20))
            guard end - start >= 20 else { continue }

            let lit = Set(strip.highlighted)
            let side: LaneZone.Side = lit.contains(strip.laneCount - 1) && !lit.contains(0) ? .right
                : lit.contains(0) && !lit.contains(strip.laneCount - 1) ? .left : .middle
            let label = strip.highlighted.count == 1 ? LanePicker.label(strip.highlighted[0], of: strip.laneCount) : nil
            out.append(LaneZone(id: "zone-\(m.id)", maneuverId: m.id, startMeters: start, endMeters: end,
                                maneuverMeters: m.alongMeters, strip: strip, laneLabel: label, side: side,
                                isRoundabout: roundabout))
        }
        return out
    }

    /// The zone the car is in or about to enter, if any.
    static func active(_ zones: [LaneZone], at along: Double) -> LaneZone? {
        zones.first { along >= $0.startMeters - leadInMeters && along < $0.maneuverMeters }
    }

    /// How far through the zone the car is, 0 at its start and 1 at "be in the lane by here".
    static func progress(_ z: LaneZone, at along: Double) -> Double {
        min(1, max(0, (along - z.startMeters) / max(1, z.endMeters - z.startMeters)))
    }
}

extension Polyline {
    /// The part of the line from `from` to `to` meters along, end points included.
    func slice(from: Double, to: Double) -> [Coordinate] {
        guard to > from, let a = coordinate(atMeters: from), let b = coordinate(atMeters: to) else { return [] }
        let inner = points.indices.filter { cumulative[$0] > from && cumulative[$0] < to }.map { points[$0] }
        return [a] + inner + [b]
    }
}
