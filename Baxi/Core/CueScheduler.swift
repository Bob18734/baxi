import Foundation

// OWNER: Vardaan. Second of Vardaan's two modules (the other is LanePicker).
// Tests: BaxiTests/CueSchedulerTests.swift. Flip `isImplemented` to true when your code is in.
//
// This module answers two questions: WHEN should each cue fire (plan), and WHICH cue fires
// right now (due). CueListBuilder has already placed every cue by meters along the route.

struct CueScheduler {
    static let isImplemented = false

    /// Two cues never fire closer together than this, except a turn or roundabout cue within
    /// `urgentMeters` of its target, which always goes through.
    static let minimumGapSeconds: TimeInterval = 8
    static let urgentMeters = 120.0
    /// A cue whose target is more than this far behind the car is stale: mark it fired, never speak it.
    static let staleMeters = 50.0

    /// Sets `fireAtMeters` on every cue. Rules the tests check (lead = meters before the target):
    /// 1. laneChange: lead is `level.laneLeadFastMeters` when `roadSpeedMph` >= 40, else `level.laneLeadSlowMeters`.
    ///    Never earlier than 50 m after the previous maneuver's target (`maneuverTargets`, sorted ascending),
    ///    so the driver is not told to change lanes before finishing the last turn.
    /// 2. turn: lead 200, or 300 when roadSpeedMph >= 40.
    /// 3. roundabout: lead 400, or 600 at level .new.
    /// 4. ramp, crashCorridor: lead 400. arrive: lead 150. stopSign: lead 100, and only at a level
    ///    where `speaksStopSigns` is true; otherwise fireAtMeters stays nil.
    /// 5. speedChange: lead 400 when `speaksSpeedChanges`, else nil. schoolZone: lead 300 when
    ///    `speaksSchoolZones`, else nil.
    /// 6. signal: fires at its target (lead 0), but only for the last `level.countdownLights` signals
    ///    before the maneuver it belongs to (same `maneuverId`); earlier signals get nil.
    /// 7. fireAtMeters is never below 0.
    static func plan(_ cues: [Cue], level: ExperienceLevel, maneuverTargets: [Double]) -> [Cue] {
        // STUB so the app runs before Vardaan's version lands. Replace everything below.
        cues.map { c in
            var c = c
            c.fireAtMeters = c.kind == .signal ? c.targetMeters : max(0, c.targetMeters - 300)
            return c
        }
    }

    private(set) var fired: Set<String> = []
    private(set) var lastFireTime: TimeInterval?

    /// Returns the one cue to speak now, or nil. Rules the tests check:
    /// 1. A cue is due when fireAtMeters != nil, it has not fired, and alongMeters >= fireAtMeters.
    /// 2. A due cue whose target is more than `staleMeters` behind alongMeters is marked fired and skipped.
    /// 3. Among due cues the lowest `kind.priority` wins; ties go to the smaller targetMeters.
    /// 4. If `now - lastFireTime < minimumGapSeconds`, nothing fires, unless the winner is a turn or
    ///    roundabout cue with targetMeters - alongMeters <= urgentMeters.
    /// 5. The returned cue is recorded in `fired` and `lastFireTime` becomes `now`.
    mutating func due(from cues: [Cue], alongMeters: Double, now: TimeInterval) -> Cue? {
        // STUB. Replace with Vardaan's implementation.
        for c in cues where c.fireAtMeters != nil && !fired.contains(c.id) && alongMeters >= c.fireAtMeters! {
            fired.insert(c.id)
            lastFireTime = now
            return c
        }
        return nil
    }
}
