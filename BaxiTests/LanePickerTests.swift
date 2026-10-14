import Testing
@testable import Baxi

// Vardaan's module. These run once LanePicker.isImplemented is true.
@Suite(.enabled(if: LanePicker.isImplemented, "LanePicker is still the stub"))
struct LanePickerTests {
    // Roundabouts: turn:lanes plus the exit number.

    @Test func firstExitTakesARightLane() {
        let a = LanePicker.pick(turnLanes: "left;through|through|through;right", exitNumber: 1, totalExits: 4)!
        #expect(a.laneCount == 3 && a.laneIndex == 2 && a.laneLabel == "right lane")
    }

    @Test func lastExitTakesALeftLane() {
        let a = LanePicker.pick(turnLanes: "left;through|through;right", exitNumber: 4, totalExits: 4)!
        #expect(a.laneIndex == 0 && a.laneLabel == "left lane")
    }

    @Test func middleExitTakesAThroughLane() {
        let a = LanePicker.pick(turnLanes: "left|through|right", exitNumber: 2, totalExits: 4)!
        #expect(a.laneIndex == 1 && a.laneLabel == "middle lane")
    }

    @Test func noneAllowsEveryDirectionAndFallbacksApply() {
        // No lane allows right: rightmost lane.
        let a = LanePicker.pick(turnLanes: "left|through", exitNumber: 1, totalExits: 3)!
        #expect(a.laneIndex == 1)
        // "none" is wildcard, so exit 1 picks it when it is the rightmost right-capable lane.
        let b = LanePicker.pick(turnLanes: "left|none", exitNumber: 1, totalExits: 3)!
        #expect(b.laneIndex == 1)
        // Through exit with no through lane: leftmost lane that is not right-only.
        let c = LanePicker.pick(turnLanes: "left|right", exitNumber: 2, totalExits: 4)!
        #expect(c.laneIndex == 0)
    }

    @Test func fourLanesGetNumberedLabels() {
        let a = LanePicker.pick(turnLanes: "left|through|through|right", exitNumber: 2, totalExits: 4)!
        #expect(a.laneLabel == "lane 2 of 4" || a.laneLabel == "lane 3 of 4")
        #expect(LanePicker.pick(turnLanes: nil, exitNumber: 1, totalExits: 4) == nil)
        #expect(LanePicker.pick(turnLanes: "", exitNumber: 1, totalExits: 4) == nil)
    }

    // Ordinary turns.

    @Test func rightTurnUsesRightmostRightCapableLane() {
        let a = LanePicker.pickForTurn(turnLanes: "left|through;right|right", direction: .right)!
        #expect(a.laneIndex == 2 && a.laneLabel == "right lane")
        #expect(a.reason.lowercased().contains("right"))
    }

    @Test func leftTurnUsesLeftmostLeftCapableLane() {
        let a = LanePicker.pickForTurn(turnLanes: "left|left;through|through", direction: .left)!
        #expect(a.laneIndex == 0)
    }

    @Test func throughPrefersTheMiddleThroughLane() {
        let a = LanePicker.pickForTurn(turnLanes: "left|through|through|right", direction: .through)!
        #expect(a.laneIndex == 1 || a.laneIndex == 2)
        let b = LanePicker.pickForTurn(turnLanes: "left|right", direction: .through)!
        #expect(b.laneIndex == 1 || b.laneIndex == 0)   // no through lane: the middle one, either is acceptable for 2 lanes
    }
}
