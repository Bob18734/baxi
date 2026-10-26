import Foundation
import SwiftData

/// One supervised practice drive, stored on the phone. Day and night minutes are split at sunset
/// and sunrise by Daylight.split. Drives done without the app can be added by hand (manual).
@Model
final class DriveRecord {
    var id: UUID
    var start: Date
    var end: Date
    var dayMinutes: Int
    var nightMinutes: Int
    var level: String
    var routeTitle: String
    var distanceMeters: Double
    var cuesSpoken: Int
    var manual: Bool = false
    /// Practice.encode of the skills this drive practiced; empty for drives added by hand or saved before Oct 14.
    var skillsJSON: String = ""
    /// DriveHabits.encode of how the drive went; empty for drives added by hand or saved before Oct 24.
    var habitsJSON: String = ""
    /// Made up by Settings > "Show the app's states" to show Baxi off; removed again by the same screen.
    var sample: Bool = false

    init(start: Date, end: Date, dayMinutes: Int, nightMinutes: Int, level: ExperienceLevel, routeTitle: String,
         distanceMeters: Double, cuesSpoken: Int, manual: Bool = false, skills: SkillCounts = [:], habits: HabitReport? = nil,
         sample: Bool = false) {
        id = UUID()
        self.start = start; self.end = end
        self.dayMinutes = dayMinutes; self.nightMinutes = nightMinutes
        self.level = level.rawValue
        self.routeTitle = routeTitle
        self.distanceMeters = distanceMeters
        self.cuesSpoken = cuesSpoken
        self.manual = manual
        self.skillsJSON = Practice.encode(skills)
        self.habitsJSON = DriveHabits.encode(habits)
        self.sample = sample
    }

    var habits: HabitReport? { DriveHabits.decode(habitsJSON) }

    var skills: SkillCounts { Practice.decode(skillsJSON) }

    var row: LogRow {
        LogRow(start: start, end: end, dayMinutes: dayMinutes, nightMinutes: nightMinutes, routeTitle: routeTitle,
               distanceMeters: distanceMeters, manual: manual, id: id)
    }
}
