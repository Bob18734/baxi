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

    init(start: Date, end: Date, dayMinutes: Int, nightMinutes: Int, level: ExperienceLevel, routeTitle: String,
         distanceMeters: Double, cuesSpoken: Int, manual: Bool = false) {
        id = UUID()
        self.start = start; self.end = end
        self.dayMinutes = dayMinutes; self.nightMinutes = nightMinutes
        self.level = level.rawValue
        self.routeTitle = routeTitle
        self.distanceMeters = distanceMeters
        self.cuesSpoken = cuesSpoken
        self.manual = manual
    }

    var row: LogRow {
        LogRow(start: start, end: end, dayMinutes: dayMinutes, nightMinutes: nightMinutes, routeTitle: routeTitle,
               distanceMeters: distanceMeters, manual: manual)
    }
}
