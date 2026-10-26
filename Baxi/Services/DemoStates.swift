import Foundation
import SwiftData

/// The states a judge should see, one tap each (Settings > "Show the app's states"): the first launch, a driver with
/// no hours, a few weeks in, nearly licensed, the requirement met, and hours brought from before Baxi. Each one
/// sets the level and the hours before Baxi and swaps in made-up drives marked `sample`, so they can be removed
/// again without touching the drives the driver really logged.
enum DemoState: String, CaseIterable, Identifiable {
    case firstLaunch, brandNew, weeksIn, nearlyLicensed, requirementMet, priorHours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstLaunch: "First launch"
        case .brandNew: "Brand new, no hours"
        case .weeksIn: "Three weeks in"
        case .nearlyLicensed: "Nearly licensed"
        case .requirementMet: "Requirement met"
        case .priorHours: "Came with hours from before Baxi"
        }
    }

    var detail: String {
        switch self {
        case .firstLaunch: "The welcome pages and setup, as on the day Baxi is installed"
        case .brandNew: "Level New, an empty log, Home says to start with First drive"
        case .weeksIn: "Getting comfortable, 9 drives, 11 hours, skills starting to fill"
        case .nearlyLicensed: "Nearly licensed, 34 drives, 46 hours, most skills test-ready"
        case .requirementMet: "50 hours and 10 at night done, every skill goal met"
        case .priorHours: "18 hours logged on paper before Baxi, then 4 drives in the app"
        }
    }

    var level: ExperienceLevel {
        switch self {
        case .firstLaunch, .weeksIn, .priorHours: .gettingComfortable
        case .brandNew: .new
        case .nearlyLicensed, .requirementMet: .nearlyLicensed
        }
    }

    var prior: PriorHours {
        self == .priorHours ? PriorHours(dayMinutes: 15 * 60, nightMinutes: 3 * 60) : PriorHours()
    }
}

enum DemoStates {
    /// The drives for a state, newest last. Deterministic, so the same state always looks the same.
    static func drives(for state: DemoState, now: Date = Date()) -> [DriveRecord] {
        // Each state's story in numbers: drives, the days they span, total minutes, night minutes, and how far
        // along the six skills are (1 = every goal met).
        let count: Int, days: Int, targetMinutes: Int, targetNight: Int, skillShare: Double
        switch state {
        case .firstLaunch, .brandNew: return []
        case .weeksIn: (count, days, targetMinutes, targetNight, skillShare) = (9, 20, 11 * 60 + 20, 2 * 60 + 10, 0.3)
        case .nearlyLicensed: (count, days, targetMinutes, targetNight, skillShare) = (34, 120, 46 * 60 + 25, 8 * 60 + 40, 0.9)
        case .requirementMet: (count, days, targetMinutes, targetNight, skillShare) = (38, 135, 52 * 60 + 30, 11 * 60 + 15, 1.15)
        case .priorHours: (count, days, targetMinutes, targetNight, skillShare) = (4, 12, 3 * 60 + 10, 50, 0.12)
        }
        var seed: UInt64 = 0x5EED_0000 + UInt64(count)
        func next(_ n: Int) -> Int {   // a small, fixed sequence of "random" numbers
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(n))
        }
        let calendar = Calendar.current
        let routes = ["First drive", "Downtown and the Palladium", "Roundabout loop", "Parkway loop", "Highway ramp loop",
                      "Carmel Clay Library", "Target on Michigan Road", "Carmel High School", "Practice drive", "Clay Terrace"]
        // First the shape of each drive, then the lengths are scaled so the state's total lands where its story says.
        struct Spec { var start: Date; var minutes: Int; var hour: Int; var title: String }
        var specs: [Spec] = []
        for i in 0..<count {
            // Spread over the period, oldest first; never two on the same day.
            let daysAgo = Double(days) * Double(count - i) / Double(count + 1) + Double(next(2))
            let dayStart = calendar.startOfDay(for: now.addingTimeInterval(-daysAgo * 86_400))
            // Evenings are common once the night hours are in reach, so those states can hold their night minutes.
            let hour = state == .requirementMet || state == .nearlyLicensed
                ? [8, 10, 13, 15, 16, 17, 18, 18, 19, 19, 20][next(11)] : [8, 10, 11, 13, 14, 15, 16, 16, 17, 18, 19][next(11)]
            let start = dayStart.addingTimeInterval(Double(hour * 3600 + next(12) * 5 * 60))
            specs.append(Spec(start: start, minutes: [25, 32, 38, 45, 52, 60, 75, 90][next(8)], hour: hour, title: routes[next(routes.count)]))
        }
        let raw = specs.reduce(0) { $0 + $1.minutes }
        let scale = Double(targetMinutes) / Double(max(1, raw))
        // The evening drives carry the night minutes, scaled so the state's night total lands on its story too.
        let eveningRaw = specs.filter { $0.hour >= 18 }.reduce(0) { $0 + $1.minutes }
        let nightScale = eveningRaw > 0 ? Double(targetNight) / (Double(eveningRaw) * scale) : 0
        // Skills: at skillShare 1 every goal is reached. Below it, the roundabout skills run ahead (Carmel is all
        // roundabouts) and the highway ones behind, so "nearly licensed" shows most rings full but not all.
        let lean: [Double] = [1.25, 1.2, 0.75, 0.7, 1.1, 0.9]
        let totalSkill = Skill.allCases.enumerated().map { k, skill in
            Double(skill.goal) * (skillShare >= 1 ? max(1, min(1.3, skillShare * lean[k])) : skillShare * lean[k])
        }
        var out: [DriveRecord] = []
        for (index, spec) in specs.enumerated() {
            let minutes = max(20, Int((Double(spec.minutes) * scale / 5).rounded()) * 5)
            let night = spec.hour >= 18 ? min(minutes, Int((Double(minutes) * min(1, nightScale)).rounded())) : 0
            let title = spec.title
            let manual = title == "Practice drive" || title == "Clay Terrace"
            // This drive's share of each skill: its slice of the state's total, by position, so the counts add up
            // exactly. Drives added by hand practise nothing Baxi can count.
            var skills: SkillCounts = [:]
            if !manual {
                let driven = specs.enumerated().filter { !["Practice drive", "Clay Terrace"].contains($0.element.title) }.map(\.offset)
                if let slot = driven.firstIndex(of: index) {
                    for (k, skill) in Skill.allCases.enumerated() {
                        let before = Int((totalSkill[k] * Double(slot) / Double(driven.count)).rounded())
                        let after = Int((totalSkill[k] * Double(slot + 1) / Double(driven.count)).rounded())
                        if after > before { skills[skill] = after - before }
                    }
                }
            }
            let rolling = next(4) == 0 ? 1 : 0, over = next(3) == 0
            let habits = manual ? nil : HabitReport(trackedMinutes: Double(minutes), overLimitShare: over ? 0.03 : 0,
                                                    topOverMph: over ? 7 : nil, schoolZoneTopMph: nil,
                                                    stopSigns: 3 + next(3), fullStops: 3 + next(3) - rolling, hardBrakes: next(5) == 0 ? 1 : 0,
                                                    merges: skills[.highwayMerge] ?? 0, mergesUpToSpeed: skills[.highwayMerge] ?? 0,
                                                    score: 100 - 8 * rolling - (over ? 6 : 0) - 3 * next(3), isDemo: false)
            out.append(DriveRecord(start: spec.start, end: spec.start.addingTimeInterval(Double(minutes) * 60),
                                   dayMinutes: minutes - night, nightMinutes: night, level: state.level, routeTitle: title,
                                   distanceMeters: manual ? 0 : Double(minutes) * 550, cuesSpoken: manual ? 0 : 14 + next(10),
                                   manual: manual, skills: skills, habits: habits, sample: true))
        }
        return out
    }

    /// Puts the phone in `state`: the level, the hours before Baxi, and the sample drives (the previous samples go).
    /// `replacingAll` also removes the driver's own drives (screenshots only), so the state is exactly its story.
    @MainActor static func apply(_ state: DemoState, store: AppStore, context: ModelContext, replacingAll: Bool = false) {
        if replacingAll { ((try? context.fetch(FetchDescriptor<DriveRecord>())) ?? []).forEach(context.delete) }
        removeSamples(context)
        store.level = state.level
        store.priorHours = state.prior
        for d in drives(for: state) { context.insert(d) }
        try? context.save()
    }

    @MainActor static func removeSamples(_ context: ModelContext) {
        let samples = (try? context.fetch(FetchDescriptor<DriveRecord>(predicate: #Predicate { $0.sample }))) ?? []
        samples.forEach(context.delete)
        try? context.save()
    }
}
