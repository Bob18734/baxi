import Foundation

/// What a new driver has practiced, beyond hours: the situations Indiana's 50 hours are meant to cover.
/// The goals are Baxi's own suggestion (not from the statute or the Driver's Manual), and the README says so.
enum Skill: String, CaseIterable, Codable, Identifiable {
    case singleLaneRoundabout, multiLaneRoundabout, highwayMerge, exitRamp, laneTurn, fastRoadMiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .singleLaneRoundabout: "Single-lane roundabouts"
        case .multiLaneRoundabout: "Two-lane roundabouts"
        case .highwayMerge: "Highway merges"
        case .exitRamp: "Exit ramps"
        case .laneTurn: "Turns from a multi-lane road"
        case .fastRoadMiles: "Miles at 45 mph or more"
        }
    }

    /// How many to practice before the driving test. Baxi's suggestion.
    var goal: Int {
        switch self {
        case .singleLaneRoundabout: 20
        case .multiLaneRoundabout: 10
        case .highwayMerge: 6
        case .exitRamp: 6
        case .laneTurn: 10
        case .fastRoadMiles: 25
        }
    }
}

typealias SkillCounts = [Skill: Int]

enum Practice {
    static let fastMph = 45
    static let roundaboutMatchMeters = 80.0

    /// The skills in a set of maneuvers (what a drive handled, or what a route contains), plus miles on
    /// fast roads. Roundabouts are split by the mapped circle's lane count.
    static func count(maneuvers: [Maneuver], features: [RoadFeature], fastMeters: Double) -> SkillCounts {
        let circles = features.filter { [.singleLaneRoundabout, .multiLaneRoundabout, .interchangeRoundabout].contains($0.kind) }
        var out: SkillCounts = [:]
        for m in maneuvers {
            switch m.kind {
            case .roundabout:
                let rb = circles.min { Geo.distanceMeters($0.coordinate, m.location) < Geo.distanceMeters($1.coordinate, m.location) }
                    .flatMap { Geo.distanceMeters($0.coordinate, m.location) <= roundaboutMatchMeters ? $0 : nil }
                out[(rb?.lanes ?? 1) >= 2 ? .multiLaneRoundabout : .singleLaneRoundabout, default: 0] += 1
            case .merge, .onRamp: out[.highwayMerge, default: 0] += 1
            case .offRamp: out[.exitRamp, default: 0] += 1
            case .turn where (m.laneCount ?? 0) > 1: out[.laneTurn, default: 0] += 1
            default: break
            }
        }
        let miles = Int((fastMeters / 1609.34).rounded())
        if miles > 0 { out[.fastRoadMiles] = miles }
        return out
    }

    /// Meters of the route posted at `fastMph` or more, from a speed profile.
    static func fastMeters(route length: Double, speeds: [(along: Double, mph: Int)]) -> Double {
        var total = 0.0
        for (a, b) in zip(speeds, speeds.dropFirst()) where a.mph >= fastMph && b.along - a.along <= 60 {
            total += b.along - a.along
        }
        return min(total, length)
    }

    static func total(_ drives: [SkillCounts]) -> SkillCounts {
        drives.reduce(into: [:]) { acc, d in for (k, v) in d { acc[k, default: 0] += v } }
    }

    /// How much of each goal is still to do, 0 when met.
    static func remaining(_ done: SkillCounts) -> SkillCounts {
        Dictionary(uniqueKeysWithValues: Skill.allCases.map { ($0, max(0, $0.goal - (done[$0] ?? 0))) })
    }

    struct Suggestion: Equatable {
        let presetId: String
        let covers: [(skill: Skill, count: Int)]
        static func == (a: Suggestion, b: Suggestion) -> Bool {
            a.presetId == b.presetId && a.covers.map(\.skill) == b.covers.map(\.skill) && a.covers.map(\.count) == b.covers.map(\.count)
        }
    }

    /// The practice route that does the most for what is still to do: each skill's reps on the route,
    /// capped at what remains, weighted so a skill furthest from its goal counts most. nil when every
    /// goal is met or no route helps.
    static func suggest(done: SkillCounts, routes: [(id: String, skills: SkillCounts)]) -> Suggestion? {
        let left = remaining(done)
        func useful(_ r: SkillCounts) -> [(skill: Skill, count: Int)] {
            Skill.allCases.compactMap { s in
                let n = min(r[s] ?? 0, left[s] ?? 0)
                return n > 0 ? (s, n) : nil
            }
        }
        func score(_ r: SkillCounts) -> Double {
            useful(r).reduce(0) { $0 + Double($1.count) / Double($1.skill.goal) * (Double(left[$1.skill] ?? 0) / Double($1.skill.goal)) }
        }
        guard let best = routes.max(by: { score($0.skills) < score($1.skills) }), score(best.skills) > 0 else { return nil }
        return Suggestion(presetId: best.id, covers: useful(best.skills).sorted { $0.count > $1.count })
    }

    // MARK: Levels

    static let levelTitles = ["Not yet", "Started", "Steady", "Confident", "Test-ready"]

    /// A skill's level, 0 to 4, at a quarter, half, three quarters and all of its goal (rounded up), and how
    /// many more reps reach the next level (nil at the top).
    static func level(_ skill: Skill, count: Int) -> (level: Int, title: String, toNext: Int?) {
        let marks = (1...4).map { Int((Double(skill.goal) * Double($0) / 4).rounded(.up)) }
        let level = marks.filter { count >= $0 }.count
        return (level, levelTitles[level], level < 4 ? marks[level] - count : nil)
    }

    /// The skills whose level went up between two totals, with the new level.
    static func levelUps(before: SkillCounts, after: SkillCounts) -> [(skill: Skill, level: Int)] {
        Skill.allCases.compactMap { s in
            let now = level(s, count: after[s] ?? 0).level
            return now > level(s, count: before[s] ?? 0).level ? (s, now) : nil
        }
    }

    // Stored on DriveRecord as JSON text, so old records (empty) still load.
    static func encode(_ c: SkillCounts) -> String {
        let plain = Dictionary(uniqueKeysWithValues: c.map { ($0.key.rawValue, $0.value) })
        return (try? String(data: JSONEncoder().encode(plain), encoding: .utf8)) ?? ""
    }

    static func decode(_ s: String) -> SkillCounts {
        guard let d = s.data(using: .utf8), let plain = try? JSONDecoder().decode([String: Int].self, from: d) else { return [:] }
        return Dictionary(uniqueKeysWithValues: plain.compactMap { k, v in Skill(rawValue: k).map { ($0, v) } })
    }
}
