import Foundation
import Testing
@testable import Baxi

struct DaylightTests {
    let carmel = Coordinate(lat: 39.9784, lon: -86.1180)
    let eastern = TimeZone(identifier: "America/Indiana/Indianapolis")!

    func local(_ s: String) -> Date {
        let f = DateFormatter()
        f.timeZone = eastern; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    @Test func carmelMidOctober() throws {
        // Published tables for Indianapolis on Oct 14: sunrise about 7:58 am, sunset about 7:06 pm EDT.
        let s = try #require(Daylight.sunriseSunset(on: local("2026-10-14 12:00"), at: carmel, timeZone: eastern))
        #expect(abs(s.sunrise.timeIntervalSince(local("2026-10-14 07:58"))) < 8 * 60)
        #expect(abs(s.sunset.timeIntervalSince(local("2026-10-14 19:06"))) < 8 * 60)
    }

    @Test func carmelSummerSolstice() throws {
        // Indianapolis on Jun 21: sunrise about 6:16 am, sunset about 9:16 pm EDT.
        let s = try #require(Daylight.sunriseSunset(on: local("2026-06-21 12:00"), at: carmel, timeZone: eastern))
        #expect(abs(s.sunrise.timeIntervalSince(local("2026-06-21 06:16"))) < 8 * 60)
        #expect(abs(s.sunset.timeIntervalSince(local("2026-06-21 21:16"))) < 8 * 60)
    }

    @Test func driveAcrossSunsetSplits() throws {
        let sunset = try #require(Daylight.sunriseSunset(on: local("2026-10-14 12:00"), at: carmel, timeZone: eastern)).sunset
        let split = Daylight.split(start: sunset.addingTimeInterval(-20 * 60), end: sunset.addingTimeInterval(25 * 60),
                                   at: carmel, timeZone: eastern)
        #expect(split.day == 20)
        #expect(split.night == 25)
    }

    @Test func noonAndMidnightDrives() {
        #expect(Daylight.split(start: local("2026-10-14 12:00"), end: local("2026-10-14 12:30"), at: carmel, timeZone: eastern) == (30, 0))
        #expect(Daylight.split(start: local("2026-10-14 23:40"), end: local("2026-10-15 00:20"), at: carmel, timeZone: eastern) == (0, 40))
        #expect(Daylight.split(start: local("2026-10-14 12:00"), end: local("2026-10-14 12:00"), at: carmel, timeZone: eastern) == (0, 0))
    }
}

struct DriveLogTests {
    let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    func row(_ day: Int, _ night: Int, title: String = "Roundabout loop") -> LogRow {
        LogRow(start: t0, end: t0.addingTimeInterval(Double(day + night) * 60), dayMinutes: day, nightMinutes: night,
               routeTitle: title, distanceMeters: 16_093.4, manual: false)
    }

    @Test func totalsCountTowardFiftyAndTen() {
        let t = DriveLog.totals([row(45, 0), row(10, 50)])
        #expect(t.minutes == 105)
        #expect(t.nightMinutes == 50)
        #expect(t.minutesLeft == 50 * 60 - 105)
        #expect(t.nightMinutesLeft == 550)
        #expect(!t.isComplete)
        #expect(DriveLog.totals([row(2400, 600)]).isComplete)
    }

    @Test func hoursAndMinutes() {
        #expect(DriveLog.hm(65) == "1:05")
        #expect(DriveLog.hm(0) == "0:00")
        #expect(DriveLog.hm(600) == "10:00")
    }

    @Test func csvHasHeaderRowsAndTotalAndQuotesCommas() {
        let csv = DriveLog.csv([row(30, 0), row(0, 20, title: "Home, then school")], timeZone: TimeZone(identifier: "UTC")!)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 4)
        #expect(lines[0].hasPrefix("Date,Start,End"))
        #expect(lines[1].contains("0:30,0:30,0:00"))
        #expect(lines[2].contains("\"Home, then school\""))
        #expect(lines[3] == "Total,,,0:50,0:30,0:20,,,")
    }
}
