import Foundation

// Written by Claude (Oct 14) at the team's request; originally set aside for Vardaan. See AI_DISCLOSURE.md.
// Tests: BaxiTests/LanePickerTests.swift.

/// Which lane to be in before a roundabout or a turn, read from the OSM `turn:lanes` tag of the
/// approach way. A `turn:lanes` value lists lanes left to right separated by `|`; each lane holds
/// one or more directions separated by `;` such as `left`, `through`, `right`, `slight_right`, `none`.
struct LaneAdvice: Equatable {
    /// Number of lanes on the approach.
    let laneCount: Int
    /// Zero-based index from the left of the lane the driver should be in.
    let laneIndex: Int
    /// Short human label such as "right lane" or "middle lane".
    let laneLabel: String
    /// One line the app can speak, such as "Right lane: exit 1 is a right turn."
    let reason: String
}

enum LanePicker {
    static let isImplemented = true

    enum TurnDirection { case left, right, through }

    /// Picks a lane for an ordinary turn at a signal or a stop.
    /// Rules the tests check:
    /// 1. `.right`: the rightmost lane that allows `right` or `slight_right`; if none allows it, the rightmost lane.
    /// 2. `.left`: the leftmost lane that allows `left` or `slight_left`; if none allows it, the leftmost lane.
    /// 3. `.through`: a lane that allows `through`, preferring the one nearest the middle; if none, the middle lane.
    /// 4. `none` or an empty entry allows every direction, and `reason` names the direction, e.g. "Right lane: right turn ahead."
    /// 5. nil when turnLanes is nil or empty.
    static func pickForTurn(turnLanes: String?, direction: TurnDirection) -> LaneAdvice? {
        guard let lanes = parse(turnLanes) else { return nil }
        let idx: Int
        let what: String
        switch direction {
        case .right:
            idx = lanes.lastIndex { allows($0, right) } ?? lanes.count - 1
            what = "right turn ahead"
        case .left:
            idx = lanes.firstIndex { allows($0, left) } ?? 0
            what = "left turn ahead"
        case .through:
            idx = nearestMiddle(lanes.indices.filter { allows(lanes[$0], through) }, count: lanes.count) ?? lanes.count / 2
            what = "going straight"
        }
        return advice(idx, of: lanes.count, reason: what)
    }

    /// Picks a lane for a roundabout exit.
    /// - Parameters:
    ///   - turnLanes: the approach way's `turn:lanes` tag, for example `left;through|through|right`.
    ///   - exitNumber: the exit the route takes, counting from 1 (OSRM gives this).
    ///   - totalExits: legs on the roundabout, from the classifier.
    /// Rules the tests check:
    /// 1. Exit 1 of N (a right turn): a lane that allows `right` or `slight_right`; if none, the rightmost lane.
    /// 2. The left turn or U-turn (`totalExits` counts the leg you enter on, so on a four-way roundabout
    ///    exit 3 is the left turn and exit 4 the U-turn): a lane that allows `left` or `slight_left`; if none, the leftmost lane.
    /// 3. Any other exit (going through): a lane that allows `through`; if none, the leftmost lane that is not right-only.
    /// 4. `none` or an empty lane entry allows every direction.
    /// 5. laneLabel is "left lane", "right lane", "middle lane", or "lane 2 of 4" style for the inner lanes of 4+.
    static func pick(turnLanes: String?, exitNumber: Int, totalExits: Int) -> LaneAdvice? {
        guard let lanes = parse(turnLanes) else { return nil }
        let idx: Int
        let what: String
        switch exitSide(exitNumber: exitNumber, totalExits: totalExits) {
        case .right:
            idx = lanes.lastIndex { allows($0, right) } ?? lanes.count - 1
            what = "exit 1 is a right turn"
        case .left:
            idx = lanes.firstIndex { allows($0, left) } ?? 0
            what = "exit \(exitNumber) turns left"
        case .through:
            let throughLanes = lanes.indices.filter { allows(lanes[$0], through) }
            idx = nearestMiddle(throughLanes, count: lanes.count)
                ?? lanes.firstIndex { !isRightOnly($0) } ?? 0
            what = "exit \(exitNumber) goes straight through"
        }
        return advice(idx, of: lanes.count, reason: what)
    }

    /// Every lane that can take a straight-through roundabout exit, left to right. Baxi says
    /// "either lane" when there is more than one, rather than asking for a needless lane change.
    static func throughLanes(_ turnLanes: String?) -> [Int] {
        guard let lanes = parse(turnLanes) else { return [] }
        return lanes.indices.filter { allows(lanes[$0], through) }
    }

    // MARK: Helpers

    private static let right: Set<String> = ["right", "slight_right", "sharp_right"]
    private static let left: Set<String> = ["left", "slight_left", "sharp_left", "reverse"]
    private static let through: Set<String> = ["through"]

    /// Lanes left to right, each a set of directions; an empty set means `none` (any direction).
    private static func parse(_ turnLanes: String?) -> [Set<String>]? {
        guard let turnLanes, !turnLanes.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return turnLanes.split(separator: "|", omittingEmptySubsequences: false).map { lane in
            Set(lane.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty && $0 != "none" })
        }
    }

    private static func allows(_ lane: Set<String>, _ directions: Set<String>) -> Bool {
        lane.isEmpty || !lane.isDisjoint(with: directions)
    }

    private static func isRightOnly(_ lane: Set<String>) -> Bool { !lane.isEmpty && lane.isSubset(of: right) }

    /// The candidate closest to the middle of the road; ties go to the left.
    private static func nearestMiddle(_ candidates: [Int], count: Int) -> Int? {
        let middle = Double(count - 1) / 2
        return candidates.min { (abs(Double($0) - middle), $0) < (abs(Double($1) - middle), $1) }
    }

    static func label(_ index: Int, of count: Int) -> String {
        if index == 0 { return "left lane" }
        if index == count - 1 { return "right lane" }
        return count >= 4 ? "lane \(index + 1) of \(count)" : "middle lane"
    }

    /// The label as it is said after "move to" or "stay in": "the left lane", but "lane 2 of 4".
    static func spoken(_ label: String) -> String { label.hasPrefix("lane ") ? label : "the \(label)" }

    /// Standard markings for a multi-lane roundabout approach, for when OpenStreetMap has no
    /// turn:lanes tag: left lane for left and through, right lane for right and through.
    static func standardRoundaboutLanes(_ lanes: Int) -> String? {
        guard lanes >= 2 else { return nil }
        return (["left;through"] + Array(repeating: "through", count: min(lanes, 3) - 2) + ["through;right"]).joined(separator: "|")
    }

    /// Where an exit leaves the roundabout, counting the entry leg in `totalExits`.
    enum ExitSide { case right, through, left }
    static func exitSide(exitNumber: Int, totalExits: Int) -> ExitSide {
        if exitNumber <= 1 { return .right }
        return exitNumber >= max(2, totalExits - 1) ? .left : .through
    }

    private static func advice(_ index: Int, of count: Int, reason: String) -> LaneAdvice {
        let label = label(index, of: count)
        return LaneAdvice(laneCount: count, laneIndex: index, laneLabel: label,
                          reason: "\(label.prefix(1).uppercased() + label.dropFirst()): \(reason).")
    }
}
