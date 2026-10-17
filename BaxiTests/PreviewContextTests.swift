import Foundation
import Testing
@testable import Baxi

struct PreviewContextTests {
    private func route(_ line: Polyline = TestRoute.line, maneuvers: [Maneuver] = []) -> PlannedRoute {
        PlannedRoute(id: "preview", name: "Preview test", polyline: line, maneuvers: maneuvers,
                     distanceMeters: line.lengthMeters, durationSeconds: 200, source: "test")
    }

    private func study(north: Double = 0, link: String? = "https://example.org/study.pdf#page=7") -> IntersectionStudies.Intersection {
        let p = TestRoute.point(metersEast: 700, metersNorth: north)
        return .init(id: 7, name: "Test intersection", jurisdiction: nil, lat: p.lat, lon: p.lon,
                     aadt: nil, fatal: 0, incapacitating: nil, nonIncapacitating: nil,
                     propertyDamageOnly: nil, total: 12, studyURL: link)
    }

    private func crash(north: Double = 0, month: Int = 3) -> FARSCrashes.Crash {
        let p = TestRoute.point(metersEast: 700, metersNorth: north)
        return .init(case: "180001", city: "Carmel", lat: p.lat, lon: p.lon,
                     road: "Test Road", crossRoad: "", intersectionType: "Not an Intersection",
                     light: "Daylight", month: month, hour: 12, fatals: 1)
    }

    @Test func previewMatchesStudiesAtFiftyMetersWithoutAddingSpeech() {
        let near = HardSpots.find(route: route(), cues: [], features: [], fatalCrashes: [], studies: [study(north: 45)])
        #expect(near.count == 1)
        #expect(near.first?.kind == .studyIntersection)
        #expect(near.first?.spoken.isEmpty == true)
        #expect(near.first?.context?.url?.fragment == "page=7")
        #expect(HardSpots.find(route: route(), cues: [], features: [], fatalCrashes: [], studies: [study(north: 55)]).isEmpty)
    }

    @Test func studyCueBecomesOneStudyCardNotADuplicateCorridor() {
        let cue = Cue(id: "study-7-700", kind: .crashCorridor, targetMeters: 700,
                      spokenTemplate: "Existing study cue", cardTemplate: "Existing study card",
                      laneStrip: nil, roadSpeedMph: nil, maneuverId: nil)
        let spots = HardSpots.find(route: route(), cues: [cue], features: [], fatalCrashes: [], studies: [study()])
        #expect(spots.count == 1)
        #expect(spots.first?.spoken == "Existing study cue")
        #expect(spots.first?.kind == .studyIntersection)
    }

    @Test func fatalRecordMatchesAtSeventyFiveMetersAndRemainsSilent() {
        let spots = HardSpots.find(route: route(), cues: [], features: [], fatalCrashes: [crash(north: 70)], studies: [])
        #expect(spots.count == 1)
        #expect(spots.first?.kind == .fatalCrash)
        #expect(spots.first?.spoken.isEmpty == true)
        #expect(spots.first?.context?.detail.contains("on Test Road, in daylight") == true)
        #expect(HardSpots.find(route: route(), cues: [], features: [], fatalCrashes: [crash(north: 80)], studies: []).isEmpty)
    }

    @Test func historicalCountsDistinguishMissingFromZero() {
        let context = PreviewContext.study(study(link: nil))
        #expect(context.detail.contains("Fatal crashes: 0"))
        #expect(context.detail.contains("Serious-injury crashes: not reported"))
        #expect(context.url == nil)
        #expect(PreviewContext.webURL("file:///tmp/study.pdf") == nil)
        #expect(PreviewContext.webURL("javascript:alert(1)") == nil)
        #expect(PreviewContext.webURL("not a link") == nil)
    }

    @Test func repeatedPassesKeepSeparateUniqueCardsInRouteOrder() {
        let points = TestRoute.line.points + TestRoute.line.points.dropLast().reversed()
        let spots = HardSpots.find(route: route(Polyline(points)), cues: [], features: [],
                                   fatalCrashes: [crash()], studies: [study()])
        #expect(spots.filter { $0.kind == .fatalCrash }.count == 2)
        #expect(spots.filter { $0.kind == .studyIntersection }.count == 2)
        #expect(Set(spots.map(\.id)).count == spots.count)
        #expect(spots.map(\.alongMeters) == spots.map(\.alongMeters).sorted())
    }

    @Test func missingLayersAndUnknownMonthHaveHonestFallbacks() {
        #expect(HardSpots.find(route: route(), cues: [], features: [], fatalCrashes: [], studies: []).isEmpty)
        let spots = HardSpots.find(route: route(), cues: [], features: [], fatalCrashes: [crash(month: 99)], studies: [])
        #expect(spots.first?.title == "Fatal crash record, 2023")
    }

    @Test func previewUsesCueLaneStripAndLabelsMissingRoundaboutTags() {
        let at = TestRoute.point(metersEast: 700)
        let maneuver = Maneuver(id: 1, kind: .roundabout, direction: .right, location: at, alongMeters: 700,
                                exitNumber: 1, roadName: nil, instruction: "Roundabout", laneCount: nil, validLanes: nil)
        let strip = LaneStrip(laneCount: 2, highlighted: [1], labels: ["↑", "→"])
        let cue = Cue(id: "lane-1", kind: .laneChange, targetMeters: 700, spokenTemplate: "Existing lane cue",
                      cardTemplate: "Lane", laneStrip: strip, roadSpeedMph: nil, maneuverId: 1)
        let feature = RoadFeature(id: "rb1", kind: .singleLaneRoundabout, coordinate: at, name: nil,
                                  lanes: 1, legs: 4, maxspeedMph: nil, osmIds: [1])
        let route = route(maneuvers: [maneuver])
        let missing = HardSpots.find(route: route, cues: [cue], features: [feature], fatalCrashes: [], studies: [])
        #expect(missing.first?.laneStrip == strip)
        #expect(missing.first?.mapDataNote != nil)
        #expect(missing.first?.title == "Roundabout, first exit")
        let way = OSMWay(id: 1, tags: ["junction": "roundabout", "lanes": "1"], nodes: nil, geometry: nil, lat: nil, lon: nil)
        let cache = OSMCache(source: "test", bbox: "", fetched: "", ways: [way], nodes: [])
        let tagged = HardSpots.find(route: route, cues: [cue], features: [feature], fatalCrashes: [], studies: [], cache: cache)
        #expect(tagged.first?.mapDataNote == nil)
        #expect(tagged.first?.title == "Single-lane roundabout, first exit")
    }

    @Test func turnLaneTagsCreateAPreviewEvenWhenRouterHasNoLaneCount() {
        let at = TestRoute.point(metersEast: 700)
        let maneuver = Maneuver(id: 1, kind: .turn, direction: .right, location: at, alongMeters: 700,
                                exitNumber: nil, roadName: nil, instruction: "Turn right", laneCount: nil, validLanes: nil)
        let route = route(maneuvers: [maneuver])
        #expect(HardSpots.find(route: route, cues: [], features: [], fatalCrashes: [], studies: []).isEmpty)
        let strip = LaneStrip(laneCount: 2, highlighted: [1], labels: ["↑", "→"])
        let cue = Cue(id: "lane-1", kind: .laneChange, targetMeters: 700, spokenTemplate: "Existing lane cue",
                      cardTemplate: "Lane", laneStrip: strip, roadSpeedMph: nil, maneuverId: 1)
        let spots = HardSpots.find(route: route, cues: [cue], features: [], fatalCrashes: [], studies: [])
        #expect(spots.count == 1)
        #expect(spots.first?.kind == .laneTurn)
        #expect(spots.first?.laneStrip == strip)
    }
}
