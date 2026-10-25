import Testing
import Foundation
@testable import Baxi

struct DemoStatesTests {
    static let now = Date(timeIntervalSince1970: 1_761_400_000)   // Oct 25, 2026

    @Test func eachStateTellsTheStoryItClaims() {
        func totals(_ s: DemoState) -> DriveLog.Totals { DriveLog.totals(DemoStates.drives(for: s, now: Self.now).map(\.row), prior: s.prior) }
        #expect(DemoStates.drives(for: .brandNew, now: Self.now).isEmpty)
        #expect(DemoStates.drives(for: .firstLaunch, now: Self.now).isEmpty)
        let weeks = totals(.weeksIn)
        #expect((9 * 60...14 * 60).contains(weeks.minutes), "weeks in: \(weeks.minutes) min")
        let nearly = totals(.nearlyLicensed)
        #expect((43 * 60...49 * 60).contains(nearly.minutes), "nearly: \(nearly.minutes) min")
        #expect((7 * 60...9 * 60 + 59).contains(nearly.nightMinutes) && !nearly.isComplete, "nearly: \(nearly.nightMinutes) night")
        let met = totals(.requirementMet)
        #expect(met.isComplete && met.nightMinutes < 14 * 60, "met: \(met.minutes) / \(met.nightMinutes)")
        // Skills fill over months: weeks in has none test-ready; nearly licensed has most but not all.
        func ready(_ s: DemoState) -> Int {
            let done = Practice.total(DemoStates.drives(for: s, now: Self.now).map(\.skills))
            return Skill.allCases.filter { (done[$0] ?? 0) >= $0.goal }.count
        }
        #expect(ready(.weeksIn) == 0, "weeks in: \(ready(.weeksIn)) ready")
        #expect((3...5).contains(ready(.nearlyLicensed)), "nearly: \(ready(.nearlyLicensed)) ready")
        #expect(ready(.requirementMet) == 6)
        let prior = totals(.priorHours)
        #expect(prior.minutes >= 18 * 60 && DemoStates.drives(for: .priorHours, now: Self.now).count == 4)
    }

    @Test func sampleDrivesAreMarkedPastAndNeverOverlap() {
        for s in DemoState.allCases {
            let drives = DemoStates.drives(for: s, now: Self.now).sorted { $0.start < $1.start }
            #expect(drives.allSatisfy { $0.sample && $0.end < Self.now && $0.end > $0.start })
            for (a, b) in zip(drives, drives.dropFirst()) { #expect(a.end <= b.start, "\(s): overlap") }
            // The same state is the same every time.
            #expect(DemoStates.drives(for: s, now: Self.now).map(\.start) == drives.map(\.start))
        }
    }
}
