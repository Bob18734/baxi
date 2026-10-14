import Testing
@testable import Baxi

// Vardaan's module. These run once CueScheduler.isImplemented is true.
@Suite(.enabled(if: CueScheduler.isImplemented, "CueScheduler is still the stub"))
struct CueSchedulerTests {
    func cue(_ id: String, _ kind: CueKind, at m: Double, mph: Int? = 45, maneuver: Int? = 1) -> Cue {
        Cue(id: id, kind: kind, targetMeters: m, spokenTemplate: id, cardTemplate: id, laneStrip: nil,
            roadSpeedMph: mph, maneuverId: maneuver)
    }

    @Test func laneLeadDependsOnLevelAndSpeed() {
        let fast = [cue("lane", .laneChange, at: 2000, mph: 45)]
        #expect(CueScheduler.plan(fast, level: .new, maneuverTargets: [2000]).first?.fireAtMeters == 800)
        #expect(CueScheduler.plan(fast, level: .gettingComfortable, maneuverTargets: [2000]).first?.fireAtMeters == 1200)
        #expect(CueScheduler.plan(fast, level: .nearlyLicensed, maneuverTargets: [2000]).first?.fireAtMeters == 1520)
        let slow = [cue("lane", .laneChange, at: 2000, mph: 30)]
        #expect(CueScheduler.plan(slow, level: .gettingComfortable, maneuverTargets: [2000]).first?.fireAtMeters == 1600)
    }

    @Test func laneCueWaitsUntilThePreviousManeuverIsDone() {
        let c = [cue("lane", .laneChange, at: 1000, mph: 45, maneuver: 2)]
        let planned = CueScheduler.plan(c, level: .new, maneuverTargets: [900, 1000])
        #expect(planned.first?.fireAtMeters == 950)   // not 1000 - 1200 < 0, and not before 900 + 50
    }

    @Test func fixedLeadsForOtherKinds() {
        let cues = [cue("turn", .turn, at: 1000, mph: 45), cue("turn2", .turn, at: 1000, mph: 30),
                    cue("rb", .roundabout, at: 1000), cue("ramp", .ramp, at: 1000), cue("hin", .crashCorridor, at: 1000),
                    cue("arrive", .arrive, at: 1000), cue("speed", .speedChange, at: 1000), cue("school", .schoolZone, at: 1000),
                    cue("stop", .stopSign, at: 1000)]
        let p = Dictionary(uniqueKeysWithValues: CueScheduler.plan(cues, level: .gettingComfortable, maneuverTargets: [1000]).map { ($0.id, $0.fireAtMeters) })
        #expect(p["turn"] == 700 && p["turn2"] == 800 && p["rb"] == 600 && p["ramp"] == 600 && p["hin"] == 600)
        #expect(p["arrive"] == 850 && p["speed"] == 600 && p["school"] == 700 && p["stop"] == nil)
        let n = Dictionary(uniqueKeysWithValues: CueScheduler.plan(cues, level: .new, maneuverTargets: [1000]).map { ($0.id, $0.fireAtMeters) })
        #expect(n["rb"] == 400 && n["stop"] == 900)
        let l = Dictionary(uniqueKeysWithValues: CueScheduler.plan(cues, level: .nearlyLicensed, maneuverTargets: [1000]).map { ($0.id, $0.fireAtMeters) })
        #expect(l["speed"] == nil && l["school"] == nil && l["hin"] == 600)
    }

    @Test func onlyTheLastNSignalsCountDown() {
        let signals = [cue("s1", .signal, at: 200), cue("s2", .signal, at: 500), cue("s3", .signal, at: 800), cue("s4", .signal, at: 950)]
        let two = CueScheduler.plan(signals, level: .gettingComfortable, maneuverTargets: [1000])
        #expect(two.map(\.fireAtMeters) == [nil, nil, 800, 950])
        let all = CueScheduler.plan(signals, level: .new, maneuverTargets: [1000])
        #expect(all.map(\.fireAtMeters) == [200, 500, 800, 950])
        let one = CueScheduler.plan(signals, level: .nearlyLicensed, maneuverTargets: [1000])
        #expect(one.map(\.fireAtMeters) == [nil, nil, nil, 950])
    }

    @Test func neverBelowZero() {
        #expect(CueScheduler.plan([cue("lane", .laneChange, at: 300)], level: .new, maneuverTargets: [300]).first?.fireAtMeters == 0)
    }

    @Test func dueFiresOnceInPriorityOrderWithAGap() {
        var planned = [cue("speed", .speedChange, at: 1000), cue("lane", .laneChange, at: 1000), cue("far", .turn, at: 3000)]
        planned = planned.map { var c = $0; c.fireAtMeters = $0.id == "far" ? 2800 : 600; return c }
        var s = CueScheduler()
        #expect(s.due(from: planned, alongMeters: 500, now: 0) == nil)
        #expect(s.due(from: planned, alongMeters: 600, now: 10)?.id == "lane")      // laneChange outranks speedChange
        #expect(s.due(from: planned, alongMeters: 620, now: 12) == nil)             // inside the 8 s gap
        #expect(s.due(from: planned, alongMeters: 700, now: 19)?.id == "speed")
        #expect(s.due(from: planned, alongMeters: 800, now: 30) == nil)             // nothing left that is due
        #expect(s.fired == ["lane", "speed"])
    }

    @Test func urgentTurnBypassesTheGapAndStaleCuesAreSkipped() {
        var planned = [cue("speed", .speedChange, at: 1000), cue("turn", .turn, at: 1100)]
        planned = planned.map { var c = $0; c.fireAtMeters = $0.id == "turn" ? 900 : 600; return c }
        var s = CueScheduler()
        #expect(s.due(from: planned, alongMeters: 600, now: 0)?.id == "speed")
        #expect(s.due(from: planned, alongMeters: 1000, now: 3)?.id == "turn")      // within 120 m of its target
        var stale = [cue("old", .schoolZone, at: 500)]
        stale[0].fireAtMeters = 200
        var t = CueScheduler()
        #expect(t.due(from: stale, alongMeters: 700, now: 0) == nil)                // 200 m past the target: never spoken
        #expect(t.fired.contains("old"))
    }
}
