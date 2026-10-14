import Foundation
import Testing
@testable import Baxi

struct SunGlareTests {
    let carmel = Coordinate(lat: 39.9765, lon: -86.1281)
    let tz = TimeZone(identifier: "America/Indiana/Indianapolis")!

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.timeZone = tz
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    @Test func sunIsAtTheHorizonAtSunsetAndHighAtSummerNoon() throws {
        let day = date(2026, 10, 14, 12, 0)
        let sunset = try #require(Daylight.sunriseSunset(on: day, at: carmel, timeZone: tz)?.sunset)
        let atSunset = SolarPosition.at(sunset, carmel)
        #expect(abs(atSunset.altitude) < 1.5, "altitude at sunset \(atSunset.altitude)")
        #expect(atSunset.azimuth > 250 && atSunset.azimuth < 270)          // west-southwest in October
        // June solstice, solar noon around 1:45 pm EDT in Carmel: 90 - 39.98 + 23.44 = 73.5 degrees.
        let june = (0..<120).map { SolarPosition.at(date(2026, 6, 21, 13, 0).addingTimeInterval(Double($0) * 60), carmel) }
        let top = try #require(june.max { $0.altitude < $1.altitude })
        #expect(abs(top.altitude - 73.5) < 1 && abs(top.azimuth - 180) < 3)
    }

    @Test func westboundAtSunsetHasGlareEastboundDoesNot() throws {
        let sunset = try #require(Daylight.sunriseSunset(on: date(2026, 10, 14, 12, 0), at: carmel, timeZone: tz)?.sunset)
        let start = sunset.addingTimeInterval(-30 * 60)                     // half an hour before sunset
        let west = Polyline((0...20).map { TestRoute.point(metersEast: Double(20 - $0) * 100) })
        let east = Polyline((0...20).map { TestRoute.point(metersEast: Double($0) * 100) })
        func route(_ l: Polyline) -> PlannedRoute {
            PlannedRoute(id: "g", name: "g", polyline: l, maneuvers: [], distanceMeters: 2000, durationSeconds: 150, source: "test")
        }
        #expect(!SunGlare.stretches(route: route(west), start: start).isEmpty)
        #expect(SunGlare.stretches(route: route(east), start: start).isEmpty)
        #expect(SunGlare.stretches(route: route(west), start: date(2026, 10, 14, 13, 0)).isEmpty)   // high sun: none
    }
}
