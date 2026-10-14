import Foundation

// Written by Claude (Oct 14) at the team's request; originally set aside for the partner. See AI_DISCLOSURE.md.
// Tests: BaxiTests/RoundaboutClassifierTests.swift.

/// One roundabout as it appears in OpenStreetMap: one or more ways tagged junction=roundabout that
/// share nodes, plus every other highway way that touches any of those nodes.
struct RoundaboutInput {
    /// The ways tagged junction=roundabout that form the circle (often more than one).
    let circleWays: [OSMWay]
    /// Ways that touch the circle but are not part of it: the legs (approaches and exits).
    let touchingWays: [OSMWay]
}

enum RoundaboutClass: String, Codable {
    /// One circulating lane.
    case singleLane
    /// Two or more circulating lanes.
    case multiLane
    /// A roundabout that feeds a freeway or parkway ramp (Keystone Parkway style).
    case interchange
}

struct RoundaboutClassification: Equatable {
    /// Circulating lanes, 1 or more.
    let lanes: Int
    /// Distinct legs. A two-way road counts once; a divided road's in and out carriageways count once each.
    let legs: Int
    let classification: RoundaboutClass
    /// True when the lane count came from a `lanes` tag, false when it was guessed.
    let lanesTagged: Bool
}

enum RoundaboutClassifier {
    static let isImplemented = true

    /// Rules the implementation must follow (the tests check these):
    /// 1. `lanes` is the maximum `lanes` tag across the circle ways. No tag anywhere: guess 1 and set lanesTagged=false.
    /// 2. `legs` counts the roads that meet the circle. A way whose highway tag is `service`, `footway`,
    ///    `cycleway` or `path` is not a leg. Per name (unnamed ways count alone): each two-way way is a leg,
    ///    and one-way ways pair up, one flowing in with one flowing out, as the two carriageways of a
    ///    divided road (so legs += max(in, out)). The same road continuing on the far side is a second leg.
    ///    A way that shares no node with the circle cannot be placed; same-named ones count once.
    /// 3. `interchange` when any touching way has highway `motorway_link` or `trunk_link`.
    ///    Otherwise `multiLane` when lanes >= 2, else `singleLane`.
    static func classify(_ input: RoundaboutInput) -> RoundaboutClassification {
        let tagged = input.circleWays.compactMap(\.lanes).filter { $0 > 0 }.max()
        let lanes = tagged ?? 1
        let notLegs: Set<String> = ["service", "footway", "cycleway", "path"]
        let legWays = input.touchingWays.filter { !notLegs.contains($0.highway ?? "") }
        let legs = countLegs(legWays, circle: input.circleWays)
        let ramp = legWays.contains { ["motorway_link", "trunk_link"].contains($0.highway ?? "") }
        let cls: RoundaboutClass = ramp ? .interchange : (lanes >= 2 ? .multiLane : .singleLane)
        return RoundaboutClassification(lanes: lanes, legs: legs, classification: cls, lanesTagged: tagged != nil)
    }

    /// Counts legs per name from how each way meets the circle (see rule 2).
    private static func countLegs(_ legWays: [OSMWay], circle: [OSMWay]) -> Int {
        let circleNodes = Set(circle.flatMap { $0.nodes ?? [] })
        var byName: [String: (twoWay: Int, into: Int, outOf: Int, unplaced: Int)] = [:]
        for w in legWays {
            let key = w.name.map { "name:\($0)" } ?? "id:\(w.id)"
            let nodes = w.nodes ?? []
            var tally = byName[key] ?? (0, 0, 0, 0)
            let oneway = w.tags["oneway"]
            let flow = oneway == "yes" || oneway == "1" ? 1 : (oneway == "-1" ? -1 : 0)
            if !nodes.contains(where: circleNodes.contains) {
                tally.unplaced += 1
            } else if flow == 0 || nodes.count < 2 {
                tally.twoWay += 1
            } else if circleNodes.contains(flow == 1 ? nodes.last! : nodes.first!) {
                tally.into += 1          // the way ends at the circle: traffic flows in
            } else if circleNodes.contains(flow == 1 ? nodes.first! : nodes.last!) {
                tally.outOf += 1
            } else {
                tally.twoWay += 1        // touches the circle mid-way; count it once
            }
            byName[key] = tally
        }
        return byName.values.reduce(0) { total, t in
            let placed = t.twoWay + max(t.into, t.outOf)
            return total + (placed > 0 ? placed : (t.unplaced > 0 ? 1 : 0))
        }
    }
}
