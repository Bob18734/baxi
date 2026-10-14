import Foundation
import Testing
@testable import Baxi

private final class Quiet: SpeechOutput {
    var isMuted = false
    func say(_ text: String) {}
    func stop() {}
}

struct LaneZoneTests {
    func zones(_ id: String, _ level: ExperienceLevel = .gettingComfortable) throws -> (PlannedRoute, [LaneZone]) {
        let route = try RouteService.preset(id)
        let prep = RoutePrep.make(route: route, cache: NoisyGPSTests.cache, features: NoisyGPSTests.features, highInjury: nil)
        return (route, LaneZones.build(cues: prep.planned(for: level, route: route), route: route))
    }

    @Test(arguments: ["preset_roundabouts", "preset_parkway", "preset_highway"])
    func zonesEndBeforeTheirManeuverAndNeverOverlap(_ id: String) throws {
        let (route, z) = try zones(id)
        #expect(!z.isEmpty, "no lane zones on \(id)")
        for zone in z {
            #expect(zone.startMeters < zone.endMeters && zone.endMeters < zone.maneuverMeters)
            #expect(zone.strip.highlighted.count < zone.strip.laneCount)     // "either lane" needs no zone
            #expect(route.polyline.slice(from: zone.startMeters, to: zone.endMeters).count >= 2)
        }
        for (a, b) in zip(z, z.dropFirst()) { #expect(a.maneuverMeters <= b.startMeters) }
    }

    @Test func zoneStartsWhereTheLaneCueIsSpoken() throws {
        let route = try RouteService.preset("preset_highway")
        let (_, z) = try zones("preset_highway")
        let s = DriveSession(route: route, cache: NoisyGPSTests.cache, features: NoisyGPSTests.features, highInjury: nil,
                             level: .gettingComfortable, mode: .replay(speedMultiplier: 1), speaker: Quiet())
        let said = s.simulateWholeRoute()
        // Every lane cue that was spoken was spoken inside (or just before) its zone, so the map and voice agree.
        for line in said where line.text.hasPrefix("Move to") {
            #expect(z.contains { line.meters >= $0.startMeters - LaneZones.leadInMeters && line.meters <= $0.endMeters },
                    "\(line.text) at \(Int(line.meters)) m has no zone")
        }
    }

    @Test func sideAndInstructionFollowTheLitLanes() {
        let strip = LaneStrip(laneCount: 3, highlighted: [2], labels: ["←", "↑", "→"])
        let m = Maneuver(id: 1, kind: .turn, direction: .right, location: TestRoute.point(metersEast: 1000), alongMeters: 1000,
                         exitNumber: nil, roadName: nil, instruction: "", laneCount: 3, validLanes: [2])
        let lane = Cue(id: "lane-1", kind: .laneChange, targetMeters: 1000, spokenTemplate: "", cardTemplate: "", laneStrip: strip,
                       roadSpeedMph: 45, maneuverId: 1, fireAtMeters: 600)
        let route = PlannedRoute(id: "t", name: "t", polyline: TestRoute.line, maneuvers: [m], distanceMeters: 2000,
                                 durationSeconds: 100, source: "test")
        let z = LaneZones.build(cues: [lane], route: route)
        #expect(z.count == 1 && z[0].side == .right && z[0].startMeters == 600 && z[0].endMeters == 960)
        #expect(z[0].instruction == "Move to the right lane")
        #expect(LaneZones.active(z, at: 580)?.id == "zone-1" && LaneZones.active(z, at: 1001) == nil)
        #expect(LaneZones.progress(z[0], at: 780) == 0.5)
    }
}
