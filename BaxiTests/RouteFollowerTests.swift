import Testing
import Foundation
@testable import Baxi

/// A straight 2 km line running east along latitude 39.95. 0.001 degrees of longitude is about 85 m here.
enum TestRoute {
    static let lat = 39.95
    static let startLon = -86.15
    static func point(metersEast m: Double, metersNorth n: Double = 0) -> Coordinate {
        let kx = cos(lat * Double.pi / 180) * 6_371_000 * Double.pi / 180
        let ky = 6_371_000 * Double.pi / 180
        return Coordinate(lat: lat + n / ky, lon: startLon + m / kx)
    }
    /// Points every 100 m from 0 to 2000 m.
    static var line: Polyline { Polyline((0...20).map { point(metersEast: Double($0) * 100) }) }
}

struct PolylineTests {
    @Test func cumulativeLengthIsAboutTwoKilometers() {
        let l = TestRoute.line
        #expect(abs(l.lengthMeters - 2000) < 2)
        #expect(l.cumulative[5] > 498 && l.cumulative[5] < 502)
    }

    @Test func projectionGivesAlongAndCrossTrack() {
        let l = TestRoute.line
        let p = l.project(TestRoute.point(metersEast: 750, metersNorth: 12))!
        #expect(abs(p.alongMeters - 750) < 1.5)
        #expect(abs(p.crossTrackMeters - 12) < 0.5)
        #expect(p.segmentIndex == 7)
    }

    @Test func coordinateAtMetersRoundTrips() {
        let l = TestRoute.line
        let c = l.coordinate(atMeters: 1234)!
        #expect(abs(l.project(c)!.alongMeters - 1234) < 0.5)
        #expect(abs(l.bearing(atMeters: 500)! - 90) < 0.5)
    }

    @Test func samplesCoverTheLine() {
        let s = TestRoute.line.samples(everyMeters: 250)
        #expect(s.count == 9)
        #expect(abs(s.last!.alongMeters - 2000) < 2)
    }
}

struct RouteFollowerTests {
    @Test func progressMovesForwardAndIgnoresBackwardWobble() {
        let f = RouteFollower(polyline: TestRoute.line)
        let a = f.update(location: TestRoute.point(metersEast: 300, metersNorth: 5), at: 0)!
        let b = f.update(location: TestRoute.point(metersEast: 290, metersNorth: -5), at: 1)!   // GPS jitter backwards
        let c = f.update(location: TestRoute.point(metersEast: 420), at: 2)!
        #expect(abs(a.alongMeters - 300) < 1.5)
        #expect(b.alongMeters == a.alongMeters)
        #expect(abs(c.alongMeters - 420) < 1.5)
        #expect(abs(c.remainingMeters - 1580) < 3)
        #expect(!c.isOffRoute)
    }

    @Test func offRouteNeedsSixtyMetersForTenSeconds() {
        let f = RouteFollower(polyline: TestRoute.line)
        _ = f.update(location: TestRoute.point(metersEast: 500), at: 0)
        let early = f.update(location: TestRoute.point(metersEast: 520, metersNorth: 90), at: 4)!
        #expect(!early.isOffRoute)
        #expect(abs(early.alongMeters - 500) < 1.5)   // progress holds while off the line
        let late = f.update(location: TestRoute.point(metersEast: 540, metersNorth: 95), at: 15)!   // 11 s after the first off-line fix
        #expect(late.isOffRoute)
    }

    @Test func returningToTheLineClearsOffRoute() {
        let f = RouteFollower(polyline: TestRoute.line)
        _ = f.update(location: TestRoute.point(metersEast: 500), at: 0)
        _ = f.update(location: TestRoute.point(metersEast: 520, metersNorth: 90), at: 1)
        _ = f.update(location: TestRoute.point(metersEast: 540, metersNorth: 95), at: 12)
        let back = f.update(location: TestRoute.point(metersEast: 900, metersNorth: 3), at: 20)!
        #expect(!back.isOffRoute)
        #expect(abs(back.alongMeters - 900) < 1.5)
    }
}

struct GPXTests {
    @Test func parsesTrackPointsWithTimes() {
        let xml = """
        <?xml version="1.0"?><gpx><trk><trkseg>
        <trkpt lat="39.95" lon="-86.15"><time>2026-10-13T12:00:00Z</time></trkpt>
        <trkpt lat="39.951" lon="-86.149"><time>2026-10-13T12:00:01Z</time></trkpt>
        </trkseg></trk></gpx>
        """
        let pts = GPXTrack.parse(Data(xml.utf8))
        #expect(pts.count == 2)
        #expect(pts[1].coordinate.lat == 39.951)
        #expect(pts[1].time!.timeIntervalSince(pts[0].time!) == 1)
    }

    @Test func synthesizedTrackRoundTrips() {
        let gpx = GPXTrack.synthesize(along: TestRoute.line, speedMps: 20)
        let pts = GPXTrack.parse(Data(gpx.utf8))
        #expect(pts.count == 101)
        #expect(pts.allSatisfy { $0.time != nil })
    }
}
