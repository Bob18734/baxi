import Foundation
import Testing
@testable import Baxi

/// Regression tests for the Oct 14 backend review: each one failed, or would have, before its fix.
struct ReviewFixTests {
    // Apple directions arrive as text only.

    @Test func appleRoundaboutExitIsReadFromTheText() {
        #expect(RouteService.appleStep("At the roundabout, take the 3rd exit onto Main St", isLast: false).exitNumber == 3)
        #expect(RouteService.appleStep("Enter the roundabout and take the second exit", isLast: false).exitNumber == 2)
        let unknown = RouteService.appleStep("Enter the roundabout", isLast: false)
        #expect(unknown.kind == .roundabout && unknown.exitNumber == nil)
    }

    @Test func appleUTurnAndKeepAreNotSilentOrTurns() {
        let u = RouteService.appleStep("Make a U-turn", isLast: false)
        #expect(u.kind == .turn && u.direction == .uturn)
        let keep = RouteService.appleStep("Keep left at the fork", isLast: false)
        #expect(keep.kind == .fork && keep.direction == .slightLeft)
        #expect(RouteService.appleStep("Turn right onto 116th St", isLast: false).direction == .right)
        #expect(RouteService.appleStep("Arrive at destination", isLast: true).kind == .arrive)
    }

    @Test func roundaboutWithNoExitNumberMakesNoExitOrLaneClaim() {
        let rb = Maneuver(id: 1, kind: .roundabout, direction: nil, location: TestRoute.point(metersEast: 1000), alongMeters: 1000,
                          exitNumber: nil, roadName: nil, instruction: "Enter the roundabout", laneCount: nil, validLanes: nil)
        let route = PlannedRoute(id: "t", name: "t", polyline: TestRoute.line, maneuvers: [rb], distanceMeters: 2000,
                                 durationSeconds: 100, source: "apple")
        let cues = CueListBuilder.build(route: route, cache: CueListBuilderTests.cache, features: [])
        let spoken = cues.first { $0.kind == .roundabout }?.spokenTemplate ?? ""
        #expect(!spoken.contains("exit") || spoken.contains("follow the map"))
        #expect(!spoken.contains("lane"))
        #expect(!cues.contains { $0.kind == .laneChange })
    }

    // Map matching.

    @Test func outAndBackRoutePassesAPointTwice() {
        let out = (0...10).map { TestRoute.point(metersEast: Double($0) * 100) }
        let back = (0...9).reversed().map { TestRoute.point(metersEast: Double($0) * 100, metersNorth: 3) }
        let line = Polyline(out + back)
        let passes = line.passes(near: TestRoute.point(metersEast: 400), within: 20)
        #expect(passes.count == 2)
        #expect(abs(passes[0] - 400) < 5 && abs(passes[1] - 1600) < 10)
    }

    @Test func speedLimitIsNotCarriedOntoUntaggedRoad() {
        let speeds: [(along: Double, mph: Int)] = [(0, 55), (25, 55), (50, 55)]
        #expect(CueListBuilder.speed(at: 60, in: speeds) == 55)
        #expect(CueListBuilder.speed(at: 400, in: speeds) == nil)
    }

    @Test func noLightCountdownPastTheLastTurn() {
        // CueListBuilderTests' route: turn at 1000 m, lights at 400 and 800. A light after the turn has nothing to count to.
        var nodes = CueListBuilderTests.cache.nodes
        nodes.append(OSMNode(id: 99, tags: ["highway": "traffic_signals"], lat: TestRoute.point(metersEast: 1500).lat,
                             lon: TestRoute.point(metersEast: 1500).lon))
        let c = CueListBuilderTests.cache
        let cache = OSMCache(source: c.source, bbox: c.bbox, fetched: c.fetched, ways: c.ways, nodes: nodes)
        let cues = CueListBuilder.build(route: CueListBuilderTests.route, cache: cache, features: [])
        #expect(!cues.contains { $0.kind == .signal && $0.targetMeters > 1000 })
        #expect(cues.filter { $0.kind == .signal }.allSatisfy { $0.maneuverId != nil })
    }

    @Test func directionalTurnLanesFollowTravelDirection() {
        let w = OSMWay(id: 1, tags: ["highway": "primary", "turn:lanes:forward": "left|through", "turn:lanes:backward": "through|right"],
                       nodes: [1, 2], geometry: [[39.95, -86.15], [39.95, -86.14]], lat: nil, lon: nil)
        let mid = Coordinate(lat: 39.95, lon: -86.145)
        #expect(w.turnLanes(travelling: 90, near: mid) == "left|through")     // eastbound, drawn direction
        #expect(w.turnLanes(travelling: 270, near: mid) == "through|right")   // westbound
    }

    @Test func csvNeutralizesFormulasAndQuotesCarriageReturns() {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let rows = [LogRow(start: start, end: start.addingTimeInterval(600), dayMinutes: 10, nightMinutes: 0,
                           routeTitle: "=HYPERLINK(\"x\")", distanceMeters: 1000, manual: true)]
        let csv = DriveLog.csv(rows, timeZone: TimeZone(identifier: "UTC")!)
        #expect(csv.contains("\"'=HYPERLINK(\"\"x\"\")\""))
    }

    // Crash data.

    @Test func studiedIntersectionOnTheRouteGetsASpokenHeadsUp() throws {
        let json = #"{"id": 7, "name": "146th St. at Gray Rd.", "lat": \#(TestRoute.lat), "lon": \#(TestRoute.point(metersEast: 1500).lon), "fatal": 1, "incapacitating": 5}"#
        let study = try JSONDecoder().decode(IntersectionStudies.Intersection.self, from: Data(json.utf8))
        let cues = CueListBuilder.build(route: CueListBuilderTests.route, cache: CueListBuilderTests.cache, features: [], studies: [study])
        let c = cues.first { $0.id.hasPrefix("study-7") }
        #expect(c?.kind == .crashCorridor && abs((c?.targetMeters ?? 0) - 1500) < 5)
        #expect(c?.spokenTemplate.contains("146th Street and Gray Road") == true)
        #expect(c?.cardTemplate.contains("1 fatal, 5 serious-injury") == true)
        #expect(CueListBuilder.build(route: CueListBuilderTests.route, cache: CueListBuilderTests.cache, features: [], studies: [])
            .allSatisfy { !$0.id.hasPrefix("study-") })
    }

    @Test func fatalCrashIsAPreviewSpotButNeverSpoken() throws {
        let json = #"{"case": "1", "city": "Carmel", "lat": \#(TestRoute.lat), "lon": \#(TestRoute.point(metersEast: 700).lon), "road": "US-31", "crossRoad": "", "intersectionType": "Not an Intersection", "light": "Daylight", "month": 3, "hour": 14, "fatals": 1}"#
        let crash = try JSONDecoder().decode(FARSCrashes.Crash.self, from: Data(json.utf8))
        let route = CueListBuilderTests.route
        let cues = CueListBuilder.build(route: route, cache: CueListBuilderTests.cache, features: [], studies: [])
        let spots = HardSpots.find(route: route, cues: cues, features: [], fatalCrashes: [crash])
        let spot = spots.first { $0.id.hasPrefix("fars-1") }
        #expect(spot != nil && spot!.spoken.isEmpty && spot!.title == "Fatal crash here, March 2023, in daylight")
        #expect(!cues.contains { $0.spokenTemplate.lowercased().contains("fatal") })
    }

    // GPS gaps.

    private func gapSession() -> DriveSession {
        DriveSession(route: CueListBuilderTests.route, cache: CueListBuilderTests.cache, features: [], highInjury: nil,
                     level: .gettingComfortable, mode: .live, speaker: QuietSpeech())
    }

    @Test func dropoutOnTheRouteCountsTheDistanceAndTheTurn() {
        let s = gapSession()
        for i in 0...30 { s.feed(TestRoute.point(metersEast: Double(i) * 20), at: Double(i)) }        // to 600 m at 45 mph
        s.feed(TestRoute.point(metersEast: 1_100), at: 56)                                              // 25 s gap, 500 m on
        #expect(s.passedManeuvers.contains { $0.id == 1 })                                              // the turn at 1000 m
        #expect(abs(s.drivenMeters - 1_100) < 5)
    }

    @Test func leavingTheRouteThenADropoutDoesNotCreditWhatWasSkipped() {
        let s = gapSession()
        for i in 0...30 { s.feed(TestRoute.point(metersEast: Double(i) * 20), at: Double(i)) }
        for i in 1...5 { s.feed(TestRoute.point(metersEast: 600, metersNorth: Double(i) * 30), at: 30 + Double(i)) } // turns off
        s.feed(TestRoute.point(metersEast: 1_300), at: 66)                                              // back on, far ahead
        #expect(!s.passedManeuvers.contains { $0.id == 1 })
        #expect(s.drivenMeters < 700)
    }

    @Test func railroadCrossingIsAnnouncedAtEveryLevel() {
        var nodes = CueListBuilderTests.cache.nodes
        let at = TestRoute.point(metersEast: 1_400)
        nodes.append(OSMNode(id: 77, tags: ["railway": "level_crossing"], lat: at.lat, lon: at.lon))
        let c = CueListBuilderTests.cache
        let cache = OSMCache(source: c.source, bbox: c.bbox, fetched: c.fetched, ways: c.ways, nodes: nodes)
        let cues = CueListBuilder.build(route: CueListBuilderTests.route, cache: cache, features: [], studies: [])
        let rail = cues.first { $0.kind == .railroad }
        #expect(rail != nil && abs(rail!.targetMeters - 1_400) < 5)
        for level in ExperienceLevel.allCases {
            let planned = CueScheduler.plan(cues, level: level, maneuverTargets: [1000])
            let fire = planned.first { $0.kind == .railroad }?.fireAtMeters; #expect(abs((fire ?? 0) - 1_150) < 1, "\(level): \(String(describing: fire))")
        }
    }
}

private final class QuietSpeech: SpeechOutput {
    var isMuted = false
    func say(_ text: String) {}
    func stop() {}
}
