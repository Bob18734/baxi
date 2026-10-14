import Foundation
import SwiftData

/// One supervised practice drive, stored on the phone. Day and night minutes are split by sunset
/// (the sunset split lands Oct 18 per the plan; until then every minute counts as day).
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

    init(start: Date, end: Date, dayMinutes: Int, nightMinutes: Int, level: ExperienceLevel, routeTitle: String,
         distanceMeters: Double, cuesSpoken: Int) {
        id = UUID()
        self.start = start; self.end = end
        self.dayMinutes = dayMinutes; self.nightMinutes = nightMinutes
        self.level = level.rawValue
        self.routeTitle = routeTitle
        self.distanceMeters = distanceMeters
        self.cuesSpoken = cuesSpoken
    }
}
