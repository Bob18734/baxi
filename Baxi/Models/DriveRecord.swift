import Foundation
import SwiftData

/// One supervised practice drive, stored on the phone. Day and night minutes are split by sunset.
@Model
final class DriveRecord {
    var id: UUID
    var start: Date
    var end: Date
    var dayMinutes: Int
    var nightMinutes: Int
    var tier: Int
    var routeTitle: String
    var spotResults: [SpotResult]

    init(start: Date, end: Date, dayMinutes: Int, nightMinutes: Int, tier: Tier, routeTitle: String, spotResults: [SpotResult] = []) {
        id = UUID()
        self.start = start; self.end = end
        self.dayMinutes = dayMinutes; self.nightMinutes = nightMinutes
        self.tier = tier.rawValue
        self.routeTitle = routeTitle
        self.spotResults = spotResults
    }
}

/// What the passenger tapped for one briefed spot.
struct SpotResult: Codable, Hashable {
    enum Outcome: String, Codable { case smooth, neededHelp, skipped }
    var featureId: String
    var kind: FeatureKind
    var outcome: Outcome
}
