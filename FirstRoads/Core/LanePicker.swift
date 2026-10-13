import Foundation

// OWNER: Vardaan. Second of Vardaan's two modules. Tests: FirstRoadsTests/LanePickerTests.swift.

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
    /// One line a passenger can read aloud, such as "Right lane: exit 1 is a right turn."
    let reason: String
}

enum LanePicker {
    /// Picks a lane for a roundabout exit.
    /// - Parameters:
    ///   - turnLanes: the approach way's `turn:lanes` tag, for example `left;through|through|right`.
    ///   - exitNumber: the exit the route takes, counting from 1 (OSRM gives this).
    ///   - totalExits: legs on the roundabout, from the classifier.
    /// Rules the tests check:
    /// 1. Exit 1 of N (a right turn): a lane that allows `right` or `slight_right`; if none, the rightmost lane.
    /// 2. Last exit (a left turn or U-turn): a lane that allows `left` or `slight_left`; if none, the leftmost lane.
    /// 3. Any other exit (going through): a lane that allows `through`; if none, the leftmost lane that is not right-only.
    /// 4. `none` or an empty lane entry allows every direction.
    /// 5. laneLabel is "left lane", "right lane", "middle lane", or "lane 2 of 4" style for 4+ lanes.
    static func pick(turnLanes: String?, exitNumber: Int, totalExits: Int) -> LaneAdvice? {
        // STUB. Replace with Vardaan's implementation.
        guard let turnLanes, !turnLanes.isEmpty else { return nil }
        let lanes = turnLanes.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let idx = exitNumber == 1 ? lanes.count - 1 : 0
        return LaneAdvice(laneCount: lanes.count, laneIndex: idx,
                          laneLabel: idx == 0 ? "left lane" : "right lane",
                          reason: "Stub advice. Vardaan's lane picker replaces this.")
    }
}
