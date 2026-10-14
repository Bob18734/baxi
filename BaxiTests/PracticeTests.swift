import Foundation
import Testing
@testable import Baxi

struct PracticeTests {
    @Test func aWholePresetDriveCountsWhatItDrove() throws {
        let route = try RouteService.preset("preset_parkway")
        let s = DriveSession(route: route, cache: NoisyGPSTests.cache, features: NoisyGPSTests.features, highInjury: nil,
                             level: .gettingComfortable, mode: .replay(speedMultiplier: 1), speaker: SilentRecorder())
        s.simulateWholeRoute()
        let p = s.practiced
        let roundabouts = route.maneuvers.filter { $0.kind == .roundabout }.count
        #expect((p[.singleLaneRoundabout] ?? 0) + (p[.multiLaneRoundabout] ?? 0) == roundabouts)
        #expect((p[.multiLaneRoundabout] ?? 0) > 0)
        #expect((p[.highwayMerge] ?? 0) >= 1 && (p[.exitRamp] ?? 0) >= 1)
        #expect((p[.fastRoadMiles] ?? 0) >= 1)            // Keystone Parkway at 50 mph
    }

    @Test func suggestionFillsTheBiggestGapAndStopsWhenGoalsAreMet() {
        let roundaboutHeavy: SkillCounts = [.singleLaneRoundabout: 8, .multiLaneRoundabout: 6]
        let highway: SkillCounts = [.highwayMerge: 2, .exitRamp: 2, .fastRoadMiles: 5]
        let routes = [(id: "r", skills: roundaboutHeavy), (id: "h", skills: highway)]
        // Roundabouts done, highway untouched: the highway route.
        let done: SkillCounts = [.singleLaneRoundabout: 20, .multiLaneRoundabout: 10, .laneTurn: 10]
        #expect(Practice.suggest(done: done, routes: routes)?.presetId == "h")
        // Everything met: nothing to suggest.
        let all = Dictionary(uniqueKeysWithValues: Skill.allCases.map { ($0, $0.goal) })
        #expect(Practice.suggest(done: all, routes: routes) == nil)
    }

    @Test func countsSurviveStorageAndOldRecordsLoadEmpty() {
        let c: SkillCounts = [.exitRamp: 2, .fastRoadMiles: 7]
        #expect(Practice.decode(Practice.encode(c)) == c)
        #expect(Practice.decode("") == [:])
        #expect(Practice.total([c, [.exitRamp: 1]])[.exitRamp] == 3)
    }
}

private final class SilentRecorder: SpeechOutput {
    var isMuted = false
    func say(_ text: String) {}
    func stop() {}
}
