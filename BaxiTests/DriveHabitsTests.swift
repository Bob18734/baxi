import Foundation
import Testing
@testable import Baxi

/// Post-drive habit feedback, from one speed sample per location fix.
struct DriveHabitsTests {
    static let mph = 0.44704   // m/s per mph

    /// A sample a second at a steady speed, `along` advancing with the speed.
    static func steady(mph: Double, limit: Int?, seconds: Int, from t0: Double = 0, along a0: Double = 0) -> [SpeedSample] {
        (0..<seconds).map { i in SpeedSample(t: t0 + Double(i), along: a0 + Double(i) * mph * Self.mph, mps: mph * Self.mph, limitMph: limit) }
    }

    static func report(_ s: [SpeedSample], stops: [Double] = [], schools: [ClosedRange<Double>] = [], merges: [Double] = []) -> HabitReport? {
        DriveHabits.report(samples: s, stopSignAlongs: stops, schoolZones: schools, mergeAlongs: merges, isDemo: false)
    }

    @Test func cleanDriveScores100() throws {
        let r = try #require(Self.report(Self.steady(mph: 30, limit: 35, seconds: 300)))
        #expect(r.score == 100)
        #expect(r.overLimitShare == 0)
        #expect(r.topOverMph == nil)
        #expect(abs(r.trackedMinutes - 5) < 0.1)
        #expect(DriveHabits.tips(r).first == "Clean drive. Keep it up.")
    }

    @Test func speedingShareAndTop() throws {
        let slow = Self.steady(mph: 30, limit: 35, seconds: 150)
        let fast = Self.steady(mph: 45, limit: 35, seconds: 150, from: 150, along: slow.last!.along + 13)
        let r = try #require(Self.report(slow + fast))
        #expect(abs((r.overLimitShare ?? 0) - 0.5) < 0.02)
        #expect(r.topOverMph == 10)
        #expect(r.score == 70)
        #expect(DriveHabits.tips(r).first?.contains("Over the limit") == true)
    }

    @Test func fiveOverIsNotSpeeding() throws {
        let r = try #require(Self.report(Self.steady(mph: 40, limit: 35, seconds: 300)))
        #expect(r.overLimitShare == 0)
        #expect(r.topOverMph == nil)
    }

    @Test func fullVsRollingStop() throws {
        // 300 s at 25 mph with two stop signs at 1000 m and 2500 m; the car stops at the first, rolls through the second.
        var s: [SpeedSample] = []
        var along = 0.0
        for t in 0..<300 {
            var v = 25 * Self.mph
            if abs(along - 1000) < 12 { v = 0.4 }          // full stop
            if abs(along - 2500) < 12 { v = 3.0 }          // about 7 mph: rolling
            s.append(SpeedSample(t: Double(t), along: along, mps: v, limitMph: 25))
            along += max(v, 1)
        }
        let r = try #require(Self.report(s, stops: [1000, 2500]))
        #expect(r.stopSigns == 2)
        #expect(r.fullStops == 1)
        #expect(DriveHabits.tips(r).contains { $0.contains("1 of 2 stop signs") })
    }

    @Test func stopSignNotDrivenIsNotCounted() throws {
        let r = try #require(Self.report(Self.steady(mph: 25, limit: 25, seconds: 200), stops: [99_000]))
        #expect(r.stopSigns == 0)
    }

    @Test func hardBrakeCountedOnce() throws {
        var s = Self.steady(mph: 29, limit: 35, seconds: 200)
        let a = s.last!.along
        s += [SpeedSample(t: 200, along: a + 13, mps: 13, limitMph: 35),
              SpeedSample(t: 201, along: a + 24, mps: 9, limitMph: 35),
              SpeedSample(t: 202, along: a + 31, mps: 5, limitMph: 35)]
        s += Self.steady(mph: 11, limit: 35, seconds: 30, from: 203, along: a + 36)
        let r = try #require(Self.report(s))
        #expect(r.hardBrakes == 1)
    }

    @Test func gentleBrakeIsNotHard() throws {
        var s = Self.steady(mph: 29, limit: 35, seconds: 200)
        let a = s.last!.along
        s += (0..<5).map { i in SpeedSample(t: 200 + Double(i), along: a + Double(i) * 10, mps: 13 - Double(i) * 2, limitMph: 35) }
        let r = try #require(Self.report(s))
        #expect(r.hardBrakes == 0)
    }

    @Test func mergeUpToSpeed() throws {
        let good = Self.steady(mph: 52, limit: 55, seconds: 200)
        let r1 = try #require(Self.report(good, merges: [500]))
        #expect(r1.merges == 1 && r1.mergesUpToSpeed == 1)
        let slow = Self.steady(mph: 35, limit: 55, seconds: 200)
        let r2 = try #require(Self.report(slow, merges: [500]))
        #expect(r2.merges == 1 && r2.mergesUpToSpeed == 0)
        #expect(DriveHabits.tips(r2).contains { $0.contains("Merge") })
    }

    @Test func schoolZoneTop() throws {
        let r = try #require(Self.report(Self.steady(mph: 28, limit: 30, seconds: 200), schools: [800...1200]))
        #expect(r.schoolZoneTopMph == 28)
        #expect(r.score == 90)
        #expect(DriveHabits.tips(r).first?.contains("school zone") == true)
    }

    @Test func invalidSpeedsIgnored() throws {
        var s = Self.steady(mph: 30, limit: 35, seconds: 300)
        for i in stride(from: 0, to: s.count, by: 7) {
            s[i] = SpeedSample(t: s[i].t, along: s[i].along, mps: -1, limitMph: 35)
        }
        let r = try #require(Self.report(s))
        #expect(r.score == 100)
        #expect(r.hardBrakes == 0)
    }

    @Test func tooFewSamplesGivesNoReport() {
        #expect(Self.report(Self.steady(mph: 30, limit: 35, seconds: 90)) == nil)
    }

    @Test func noLimitsNoSpeedLine() throws {
        let r = try #require(Self.report(Self.steady(mph: 60, limit: nil, seconds: 300)))
        #expect(r.overLimitShare == nil)
        #expect(r.topOverMph == nil)
        #expect(!DriveHabits.tips(r).contains { $0.contains("limit") })
    }

    @Test func atMostThreeTips() throws {
        var s = Self.steady(mph: 50, limit: 30, seconds: 300)
        s[100] = SpeedSample(t: 100, along: s[100].along, mps: 3, limitMph: 30)
        let r = try #require(Self.report(s, stops: [s[100].along], schools: [0...500], merges: [3000]))
        #expect(DriveHabits.tips(r).count <= 3)
        #expect(r.score >= 0)
    }

    @Test func encodeRoundTrip() throws {
        let r = try #require(Self.report(Self.steady(mph: 30, limit: 35, seconds: 300)))
        #expect(DriveHabits.decode(DriveHabits.encode(r)) == r)
    }

    @Test func decodeEmptyIsNil() {
        #expect(DriveHabits.decode("") == nil)
        #expect(DriveHabits.encode(nil) == "")
    }
}
