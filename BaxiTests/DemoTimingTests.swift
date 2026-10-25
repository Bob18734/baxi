import AVFoundation
import Foundation
import Testing
@testable import Baxi

/// The judge demos, played as the phone plays them (Oct 25 audit, docs/DEMO-AUDIT.md): the replay timer at 4x on a
/// real-time clock, while each line takes the real time its recording lasts. Before the fix 35 instructions were
/// still being said when the car reached their turn.
struct DemoTimingTests {
    /// A voice that takes real time: one line at a time, the recording's length (else the estimate) plus the tone.
    final class TimedVoice: SpeechOutput {
        var isMuted = false
        var now = 0.0
        var at: () -> Double = { 0 }
        var target: () -> (Double, CueKind)? = { nil }
        private var queue: [(text: String, chime: Bool, target: (Double, CueKind)?)] = []
        private var current: (text: String, ends: Double, target: (Double, CueKind)?)?
        /// Each line said, with where the car was when it finished.
        private(set) var finished: [(text: String, endMeters: Double, target: (Double, CueKind)?)] = []
        var isSpeaking: Bool { current != nil || !queue.isEmpty }

        func say(_ text: String) { say(text, chime: false) }
        func say(_ text: String, chime: Bool) { queue.append((text, chime && !isSpeaking, target())); tick() }
        func stop() { queue.removeAll(); current = nil }

        func tick() {
            if let c = current, now >= c.ends { finished.append((c.text, at(), c.target)); current = nil }
            if current == nil, !queue.isEmpty {
                let n = queue.removeFirst()
                let seconds = VoiceLines.recording(for: n.text).flatMap { try? AVAudioPlayer(contentsOf: $0).duration }
                    ?? CueScheduler.speechSeconds(n.text)
                current = (n.text, now + (n.chime ? 0.45 : 0) + 0.15 + seconds, n.target)
            }
        }
    }

    /// Drives `id` from `from` at `multiplier` and returns what was said.
    static func play(_ id: String, from: Double? = nil, multiplier: Double = 4) throws -> (DriveSession, TimedVoice) {
        let route = try RouteService.preset(id)
        let voice = TimedVoice()
        let s = DriveSession(route: route, cache: DriveSessionTests.cache, features: DriveSessionTests.features, highInjury: nil,
                             level: .gettingComfortable, mode: .replay(speedMultiplier: multiplier), speaker: voice)
        voice.at = { s.progress?.alongMeters ?? from ?? 0 }
        voice.target = { s.lastCue.map { ($0.targetMeters, $0.kind) } }
        if let from { s.skip(toMeters: from) }
        s.start()
        var t = 0.0
        while !s.isFinished && t < 3 * 3600 {
            t += 0.25; voice.now = t
            s.advanceReplay(tick: 0.25, multiplier: multiplier)
            voice.tick()
        }
        while voice.isSpeaking { t += 0.25; voice.now = t; voice.tick() }
        return (s, voice)
    }

    @Test(arguments: [("preset_highway", 4_400.0), ("preset_downtown", 0), ("preset_roundabouts", 0)])
    func everyInstructionIsHeardBeforeItsManeuverAt4x(_ run: (String, Double)) throws {
        let from = run.1
        let (s, voice) = try Self.play(run.0, from: from > 0 ? from : nil)
        #expect(s.isFinished)
        let instructions: Set<CueKind> = [.turn, .roundabout, .ramp, .laneChange]
        let late = voice.finished.filter { l in
            guard let (target, kind) = l.target, instructions.contains(kind), !l.text.hasPrefix("Here we go") else { return false }
            return l.endMeters > target
        }
        #expect(late.isEmpty, "\(run.0): \(late.map { "\($0.text) (finished \(Int($0.endMeters - ($0.target?.0 ?? 0))) m after)" })")
        // And every turn, roundabout and ramp ahead was actually said (a line held back until stale never reaches
        // `finished`, so "nothing late" alone would pass with it missing).
        let heard = Set(voice.finished.compactMap { $0.target.map { Int($0.0) } })
        let missing = s.cues.filter { [.turn, .roundabout, .ramp].contains($0.kind) && $0.fireAtMeters != nil
            && $0.targetMeters > from + 30 && !heard.contains(Int($0.targetMeters)) }
        #expect(missing.isEmpty, "\(run.0) never said: \(missing.map(\.spokenTemplate))")
    }

    /// The replay waits at the start until the start line has been said.
    @Test func replayWaitsForTheStartLine() throws {
        let route = try RouteService.preset("preset_firstdrive")
        let voice = TimedVoice()
        let s = DriveSession(route: route, cache: DriveSessionTests.cache, features: DriveSessionTests.features, highInjury: nil,
                             level: .gettingComfortable, mode: .replay(speedMultiplier: 4), speaker: voice)
        s.start()
        for i in 1...4 { voice.now = Double(i) * 0.25; s.advanceReplay(tick: 0.25, multiplier: 4); voice.tick() }
        #expect(voice.isSpeaking)
        #expect(s.progress == nil)   // not a single fix yet: the car hasn't moved
        var t = 1.0
        while voice.isSpeaking { t += 0.25; voice.now = t; s.advanceReplay(tick: 0.25, multiplier: 4); voice.tick() }
        for _ in 1...8 { t += 0.25; voice.now = t; s.advanceReplay(tick: 0.25, multiplier: 4); voice.tick() }
        #expect((s.progress?.alongMeters ?? 0) > 1)   // and it leaves once the line is done
    }

    /// The practice routes end with a left into the lot 24 m before the pin: a replay says it before "You've arrived".
    @Test func replaySaysTheLastTurnBeforeArriving() throws {
        let (s, voice) = try Self.play("preset_firstdrive")
        let last = try #require(s.route.maneuvers.last { $0.kind != .arrive })
        #expect(s.route.polyline.lengthMeters - last.alongMeters < DriveSession.arrivalMeters)   // inside the arrival radius
        #expect(voice.finished.contains { $0.target.map { abs($0.0 - last.alongMeters) < 1 } ?? false })
        #expect(s.passedManeuvers.last?.id == last.id)
        #expect(s.spokenLog.last?.text == DriveSession.Line.arrived)
    }

    /// A voice that never says it has finished (an interruption the system never reports) can't stall a demo.
    @Test func aStuckVoiceNeverStallsTheReplay() throws {
        final class StuckVoice: SpeechOutput {
            var isMuted = false
            var isSpeaking: Bool { true }
            func say(_ text: String) {}
            func stop() {}
        }
        let route = try RouteService.preset("preset_firstdrive")
        let s = DriveSession(route: route, cache: DriveSessionTests.cache, features: DriveSessionTests.features, highInjury: nil,
                             level: .gettingComfortable, mode: .replay(speedMultiplier: 4), speaker: StuckVoice())
        s.start()
        var ticks = 0
        while !s.isFinished && ticks < 20_000 { s.advanceReplay(tick: 0.25, multiplier: 4); ticks += 1 }
        #expect(s.isFinished)
    }
}

/// Roundabout lanes follow where the exit really goes, not the exit number (Oct 25 audit).
struct RoundaboutSideTests {
    @Test func sideFromAngle() {
        #expect(LanePicker.side(exitAngle: 10, exitNumber: 1) == .through)
        #expect(LanePicker.side(exitAngle: 330, exitNumber: 2) == .through)
        #expect(LanePicker.side(exitAngle: 90, exitNumber: 1) == .right)
        #expect(LanePicker.side(exitAngle: 270, exitNumber: 3) == .left)
        #expect(LanePicker.side(exitAngle: 180, exitNumber: 4) == .left)
        #expect(LanePicker.side(exitAngle: 180, exitNumber: 1) == .right)
        #expect(LanePicker.side(exitAngle: .nan, exitNumber: 1) == .right)
        #expect(LanePicker.side(exitAngle: .nan, exitNumber: 3) == .through)
    }

    /// Two first exits on 96th Street carry straight on past a driveway: either lane, never "use the right lane".
    @Test func firstExitThatGoesStraightTakesEitherLane() throws {
        let route = try RouteService.preset("preset_parkway")
        let prep = RoutePrep.make(route: route, cache: DriveSessionTests.cache, features: DriveSessionTests.features, highInjury: nil)
        let cues = prep.planned(for: .gettingComfortable, route: route)
        for along in [12_339.0, 12_967.0] {
            let m = try #require(route.maneuvers.first { $0.kind == .roundabout && abs($0.alongMeters - along) < 5 })
            #expect(m.exitNumber == 1)
            let cue = try #require(cues.first { $0.maneuverId == m.id && $0.kind == .roundabout })
            #expect(cue.spokenTemplate.contains("Either lane works"), "\(cue.spokenTemplate)")
        }
    }

    /// A left exit off two through-only lanes asks for the left lane.
    @Test func leftExitAsksForTheLeftLane() throws {
        let route = try RouteService.preset("preset_highway")
        let prep = RoutePrep.make(route: route, cache: DriveSessionTests.cache, features: DriveSessionTests.features, highInjury: nil)
        let cues = prep.planned(for: .gettingComfortable, route: route)
        let m = try #require(route.maneuvers.first { $0.kind == .roundabout && abs($0.alongMeters - 5_876) < 5 })
        let cue = try #require(cues.first { $0.maneuverId == m.id && $0.kind == .roundabout })
        #expect(cue.spokenTemplate.contains("Use the left lane"), "\(cue.spokenTemplate)")
    }
}

/// The lanes show from 800 m before a maneuver that has lane data, not only after its line is said.
struct UpcomingLanesTests {
    @Test func lanesShowAheadOfTheManeuver() throws {
        let route = try RouteService.preset("preset_roundabouts")
        let s = DriveSession(route: route, cache: DriveSessionTests.cache, features: DriveSessionTests.features, highInjury: nil,
                             level: .gettingComfortable, mode: .replay(speedMultiplier: 1), speaker: DemoTimingTests.TimedVoice())
        // The two-lane roundabout on 116th Street at 3,452 m has turn:lanes; the one before it is 1.1 km back.
        let exit = try #require(route.maneuvers.first { $0.kind == .roundabout && abs($0.alongMeters - 3_452) < 5 })
        let firstLine = try #require(s.cues.filter { $0.maneuverId == exit.id }.compactMap(\.fireAtMeters).min())
        let at = exit.alongMeters - 700
        #expect(at < firstLine)   // shown before anything about this exit has been said
        s.skip(toMeters: at)
        #expect(s.nextManeuver?.id == exit.id)
        let lanes = try #require(s.upcomingLanes)
        // Going straight on: both lanes that go through are lit, none asked for.
        #expect(lanes.laneCount == 3 && lanes.highlighted == [0, 1])
    }

    @Test func noLaneDataShowsNothing() throws {
        let route = try RouteService.preset("preset_firstdrive")
        let s = DriveSession(route: route, cache: DriveSessionTests.cache, features: DriveSessionTests.features, highInjury: nil,
                             level: .gettingComfortable, mode: .replay(speedMultiplier: 1), speaker: DemoTimingTests.TimedVoice())
        s.skip(toMeters: 1_100)   // ahead: a right onto West Main Street on a one-lane street
        #expect(s.upcomingLanes == nil)
    }
}
