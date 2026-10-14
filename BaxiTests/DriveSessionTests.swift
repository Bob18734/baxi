import Foundation
import Testing
@testable import Baxi

private final class Recorder: SpeechOutput {
    var isMuted = false
    var lines: [String] = []
    func say(_ text: String) { lines.append(text) }
    func stop() {}
}

/// Drives each preset end to end through DriveSession, the way the phone would, and checks what is said.
struct DriveSessionTests {
    static let cache = try! BundledData.carmelCache()
    static let features = FeatureExtractor.extract(from: cache)

    func drive(_ id: String, level: ExperienceLevel = .gettingComfortable) throws -> (DriveSession, [(meters: Double, text: String)]) {
        let route = try RouteService.preset(id)
        let s = DriveSession(route: route, cache: Self.cache, features: Self.features, highInjury: nil, level: level,
                             mode: .replay(speedMultiplier: 1), speaker: Recorder())
        return (s, s.simulateWholeRoute())
    }

    /// The judge demo skips ahead; the Arrived screen must count only what was driven after that.
    @Test func skippedStartCountsOnlyTheDrivenPart() throws {
        let route = try RouteService.preset("preset_highway")
        let s = DriveSession(route: route, cache: Self.cache, features: Self.features, highInjury: nil,
                             level: .gettingComfortable, mode: .replay(speedMultiplier: 1), speaker: Recorder())
        s.skip(toMeters: 4_400)
        s.simulateWholeRoute()
        #expect(abs(s.drivenMeters - (route.polyline.lengthMeters - 4_400)) < 30)
        #expect(!s.passedManeuvers.isEmpty)
        #expect(s.passedManeuvers.allSatisfy { $0.alongMeters > 4_400 })
        #expect(Set(s.passedManeuvers.map(\.id)).count == s.passedManeuvers.count, "a maneuver counted twice")
    }

    @Test(arguments: ["preset_roundabouts", "preset_parkway", "preset_highway"], ExperienceLevel.allCases)
    func presetDrivesEndToEnd(_ id: String, level: ExperienceLevel) throws {
        let (s, said) = try drive(id, level: level)
        #expect(s.isFinished)
        #expect(abs(s.drivenMeters - s.route.polyline.lengthMeters) < 20)
        #expect(s.passedManeuvers.count == s.route.maneuvers.filter { $0.alongMeters > 0 && $0.kind != .arrive }.count)
        #expect(said.last?.text == "You've arrived")
        #expect(said.allSatisfy { !$0.text.contains("{") && !$0.text.contains("}") })

        // Every roundabout's exit is announced before the car reaches it.
        for m in s.route.maneuvers where m.kind == .roundabout {
            guard let n = m.exitNumber else { continue }
            let ordinal = CueListBuilder.ordinal(n)
            #expect(said.contains { $0.meters <= m.alongMeters && $0.text.contains("\(ordinal) exit") },
                    "roundabout at \(Int(m.alongMeters)) m never announced its \(ordinal) exit")
        }

        // The same line is never said twice within 30 m.
        for (a, b) in zip(said, said.dropFirst()) where a.text == b.text {
            #expect(b.meters - a.meters > 30, "\"\(a.text)\" repeated at \(Int(a.meters)) m")
        }
    }

    @Test func replayIsNeverOffRoute() throws {
        let (s, said) = try drive("preset_highway")
        #expect(!said.contains { $0.text.contains("off the route") })
        #expect(s.rerouteCount == 0)
    }

    private func straightSession() -> DriveSession {
        let line = TestRoute.line
        let turn = Maneuver(id: 1, kind: .turn, direction: .right,
                            location: TestRoute.point(metersEast: 800), alongMeters: 800,
                            exitNumber: nil, roadName: "Test road", instruction: "Turn right",
                            laneCount: nil, validLanes: nil)
        let next = Maneuver(id: 2, kind: .turn, direction: .left,
                            location: TestRoute.point(metersEast: 1000), alongMeters: 1000,
                            exitNumber: nil, roadName: "Next road", instruction: "Turn left",
                            laneCount: nil, validLanes: nil)
        let route = PlannedRoute(id: "test", name: "Test", polyline: line, maneuvers: [turn, next],
                                 distanceMeters: line.lengthMeters, durationSeconds: 200, source: "preset")
        let cache = OSMCache(source: "test", bbox: "", fetched: "", ways: [], nodes: [])
        return DriveSession(route: route, cache: cache, features: [], highInjury: nil,
                            level: .gettingComfortable, mode: .replay(speedMultiplier: 1), speaker: Recorder())
    }

    @Test func reroutesPreserveOnlyDistanceActuallyDriven() {
        let s = straightSession()
        s.feed(TestRoute.point(metersEast: 200), at: 0)
        s.feed(TestRoute.point(metersEast: 400), at: 20)
        #expect(abs(s.drivenMeters - 200) < 2)
        for iteration in 1...2 {
            s.install(s.route)
            #expect(abs(s.drivenMeters - Double(iteration) * 200) < 2)
            s.feed(TestRoute.point(metersEast: 100), at: Double(iteration) * 30)
            s.feed(TestRoute.point(metersEast: 300), at: Double(iteration) * 30 + 20)
            #expect(abs(s.drivenMeters - Double(iteration + 1) * 200) < 2)
        }
    }

    @Test func noNavigationCuesWhileOffLineBeforeOffRouteTimeout() {
        let s = straightSession()
        s.feed(TestRoute.point(metersEast: 800), at: 0)
        let before = s.spokenLog.count
        s.feed(TestRoute.point(metersEast: 810, metersNorth: 100), at: 9)
        #expect(s.progress?.isOffRoute == false)
        #expect(s.spokenLog.count == before)
    }

    @Test func endingTwiceKeepsTheOriginalEndTime() {
        let s = straightSession()
        s.end()
        let end = s.endedAt
        s.end()
        #expect(s.endedAt == end)
    }
}
