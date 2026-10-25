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

    @Test func rejoiningBehindDoesNotRewindProgress() {
        let f = RouteFollower(polyline: TestRoute.line)
        _ = f.update(location: TestRoute.point(metersEast: 500), at: 0)
        _ = f.update(location: TestRoute.point(metersEast: 500, metersNorth: 100), at: 1)
        _ = f.update(location: TestRoute.point(metersEast: 400, metersNorth: 100), at: 12)
        let back = f.update(location: TestRoute.point(metersEast: 300), at: 20)!
        #expect(!back.isOffRoute)
        #expect(abs(back.alongMeters - 500) < 2)
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

struct LoopStartTests {
    @Test func firstFixOnALoopSnapsToTheStartNotTheEnd() throws {
        // A square loop about 400 m a side whose last point stops 30 m short of the start.
        let pts = [Coordinate(lat: 39.9700, lon: -86.1300), Coordinate(lat: 39.9736, lon: -86.1300),
                   Coordinate(lat: 39.9736, lon: -86.1253), Coordinate(lat: 39.9700, lon: -86.1253),
                   Coordinate(lat: 39.9700, lon: -86.12965)]
        let line = Polyline(pts)
        // The car waits 9 m from the loop's last point and 21 m from its first segment.
        let car = Coordinate(lat: 39.96998, lon: -86.12975)
        #expect(try #require(line.project(car)).alongMeters > line.lengthMeters - 50)   // a whole-line search picks the end
        let f = RouteFollower(polyline: line)
        #expect(try #require(f.update(location: car, at: 0)).alongMeters < 50)          // the follower picks the start
    }
}

/// Oct 24: a route back along a parallel street 70 m away (First drive downtown). One bad fix that lands on
/// the other street must not move the car 1,000 m along; two fixes that agree may (a real shortcut).
struct ParallelStreetTests {
    /// East 1,000 m, north 70 m, back west 1,000 m.
    static var hairpin: Polyline {
        Polyline((0...10).map { TestRoute.point(metersEast: Double($0) * 100) }
                 + [TestRoute.point(metersEast: 1000, metersNorth: 70)]
                 + (0...10).reversed().map { TestRoute.point(metersEast: Double($0) * 100, metersNorth: 70) })
    }

    @Test func oneOutlierOnTheParallelStreetIsIgnored() throws {
        let f = RouteFollower(polyline: Self.hairpin)
        var t = 0.0
        for m in stride(from: 0.0, through: 300, by: 10) { _ = f.update(location: TestRoute.point(metersEast: m), at: t); t += 1 }
        _ = f.update(location: TestRoute.point(metersEast: 310, metersNorth: 72), at: t); t += 1   // the bad fix
        let p = try #require(f.update(location: TestRoute.point(metersEast: 320), at: t))
        #expect(p.alongMeters < 400, "jumped to \(Int(p.alongMeters)) m")
        #expect(!p.isOffRoute)
    }

    @Test func twoAgreeingFixesOnTheFarPartAreFollowed() throws {
        let f = RouteFollower(polyline: Self.hairpin)
        var t = 0.0
        for m in stride(from: 0.0, through: 300, by: 10) { _ = f.update(location: TestRoute.point(metersEast: m), at: t); t += 1 }
        // The car really is on the return street now (it cut across).
        _ = f.update(location: TestRoute.point(metersEast: 300, metersNorth: 70), at: t); t += 1
        let p = try #require(f.update(location: TestRoute.point(metersEast: 290, metersNorth: 70), at: t))
        #expect(p.alongMeters > 1700)
    }
}
