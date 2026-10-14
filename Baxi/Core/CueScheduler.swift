import Foundation

// Written by Claude (Oct 14) at the team's request; originally set aside for Vardaan. See AI_DISCLOSURE.md.
// Tests: BaxiTests/CueSchedulerTests.swift.
//
// This module answers two questions: WHEN should each cue fire (plan), and WHICH cue fires
// right now (due). CueListBuilder has already placed every cue by meters along the route.

struct CueScheduler {
    static let isImplemented = true

    /// Two cues never fire closer together than this, except a turn or roundabout cue within
    /// `urgentMeters` of its target, which always goes through.
    static let minimumGapSeconds: TimeInterval = 8
    static let urgentMeters = 120.0
    /// A cue whose target is more than this far behind the car is stale: mark it fired, never speak it.
    static let staleMeters = 50.0
    static let minimumWarningSeconds: [CueKind: Double] = [.turn: 14, .roundabout: 18, .ramp: 18, .crashCorridor: 18]
    /// Spoken words per second at the normal voice speed, for knowing when a line will have finished.
    static let wordsPerSecond = 2.6

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
        let maneuvers = maneuverTargets.sorted()
        // Signals that count down: the last `countdownLights` before each maneuver.
        var counted = Set<String>()
        let signals = cues.filter { $0.kind == .signal }
        for group in Dictionary(grouping: signals, by: { $0.maneuverId ?? -1 }).values {
            let n = min(level.countdownLights, group.count)
            group.sorted { $0.targetMeters < $1.targetMeters }.suffix(n).forEach { counted.insert($0.id) }
        }
        let planned = cues.map { c in
            var c = c
            let fast = (c.roadSpeedMph ?? 0) >= 40
            let lead: Double?
            switch c.kind {
            case .laneChange: lead = fast ? level.laneLeadFastMeters : level.laneLeadSlowMeters
            case .turn: lead = fast ? 300 : 200
            case .roundabout: lead = level == .new ? 600 : 400
            case .ramp, .crashCorridor: lead = 400
            // Every level: a train crossing matters as much to a nearly licensed driver as to a new one.
            case .railroad: lead = 250
            case .arrive: lead = 150
            case .stopSign: lead = level.speaksStopSigns ? 100 : nil
            case .speedChange: lead = level.speaksSpeedChanges ? 400 : nil
            case .schoolZone: lead = level.speaksSchoolZones ? 300 : nil
            case .signal: lead = counted.contains(c.id) ? 0 : nil
            }
            guard var lead else { c.fireAtMeters = nil; return c }
            // 10. At least this many seconds of warning at the posted speed, so a fixed distance is not too
            //     short on a fast road: 300 m at 55 mph is only 12 s. (Added by Claude beyond the original rules.)
            if let mph = c.roadSpeedMph, let seconds = Self.minimumWarningSeconds[c.kind] {
                lead = max(lead, Double(mph) * 0.44704 * seconds)
            }
            var at = c.targetMeters - lead
            if let previous = maneuvers.last(where: { $0 < c.targetMeters - 1 }) {
                if c.kind == .laneChange {
                    // Never ask for a lane change before the last maneuver is finished.
                    at = max(at, min(previous + 50, c.targetMeters))
                } else if [.turn, .roundabout, .ramp, .arrive].contains(c.kind) {
                    // 9. Nor announce the next maneuver before the driver is through the last one: a
                    //    roundabout called 600 m early must not be heard before the turn that comes first.
                    //    (Added by Claude beyond the original rules.)
                    at = max(at, min(previous + 15, c.targetMeters))
                }
            }
            c.fireAtMeters = max(0, at)
            return c
        }
        // 8. A lane cue that would fire within 100 m of its own turn or roundabout cue (or after it) is
        //    dropped: that cue already names the lane, and two lane lines back to back is noise.
        //    (Added by Claude beyond the original seven rules.)
        let mainFire = Dictionary(planned.compactMap { c -> (Int, Double)? in
            guard [.turn, .roundabout].contains(c.kind), let id = c.maneuverId, let at = c.fireAtMeters else { return nil }
            return (id, at)
        }, uniquingKeysWith: min)
        return planned.map { c in
            guard c.kind == .laneChange, let id = c.maneuverId, let at = c.fireAtMeters, let main = mainFire[id],
                  at > main - 100 else { return c }
            var c = c
            c.fireAtMeters = nil
            return c
        }
    }

    private(set) var fired: Set<String> = []
    private(set) var lastFireTime: TimeInterval?
    /// When the last line returned by `due` should finish being spoken.
    private(set) var speechEndsAt: TimeInterval?

    /// Replaces the estimate from `due` with the line as it was actually said. `rate` is the user's voice
    /// speed (1 = normal); `clockScale` is how much faster than real time the caller's clock runs.
    mutating func noteSpeech(_ text: String, at now: TimeInterval, rate: Double = 1, clockScale: Double = 1) {
        speechEndsAt = now + Self.speechSeconds(text) / max(0.5, rate) * clockScale
    }

    /// About how long a line takes to say at the normal voice speed.
    static func speechSeconds(_ text: String) -> Double {
        Double(text.split(whereSeparator: { $0 == " " }).count) / wordsPerSecond + 0.4
    }

    /// Marks a cue as already handled without speaking it (a replay that starts partway along).
    /// Written by Claude, not part of Vardaan's rules; keep it when you replace the stub.
    mutating func markFired(_ id: String) { fired.insert(id) }

    /// Returns the one cue to speak now, or nil. Rules the tests check:
    /// 1. A cue is due when fireAtMeters != nil, it has not fired, and alongMeters >= fireAtMeters.
    /// 2. A due cue whose target is more than `staleMeters` behind alongMeters is marked fired and skipped.
    /// 3. Among due cues the lowest `kind.priority` wins; ties go to the smaller targetMeters.
    /// 4. If `now - lastFireTime < minimumGapSeconds`, nothing fires, unless the winner is a turn or
    ///    roundabout cue with targetMeters - alongMeters <= urgentMeters.
    /// 5. The returned cue is recorded in `fired` and `lastFireTime` becomes `now`.
    mutating func due(from cues: [Cue], alongMeters: Double, now: TimeInterval) -> Cue? {
        var winner: Cue?
        for c in cues {
            guard let at = c.fireAtMeters, alongMeters >= at, !fired.contains(c.id) else { continue }
            if alongMeters - c.targetMeters > Self.staleMeters { fired.insert(c.id); continue }
            if let w = winner, (w.kind.priority, w.targetMeters) <= (c.kind.priority, c.targetMeters) { continue }
            winner = c
        }
        guard let w = winner else { return nil }
        // 11. Nothing starts while the last line is still being said (plus a breath), so lines never
        //     queue up behind a long one. (Added by Claude beyond the original rules.)
        let speaking = speechEndsAt.map { now < $0 + 1 } ?? false
        if let last = lastFireTime, now - last < Self.minimumGapSeconds || speaking {
            let urgent = (w.kind == .turn || w.kind == .roundabout) && w.targetMeters - alongMeters <= Self.urgentMeters
            guard urgent else { return nil }
        }
        fired.insert(w.id)
        lastFireTime = now
        speechEndsAt = now + Self.speechSeconds(w.spokenTemplate)
        return w
    }
}
