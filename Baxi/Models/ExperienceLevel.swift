import Foundation

/// How much warning the driver gets. The level changes timing only, never wording or rules.
/// The numbers here are the app's own design (not from the Indiana Driver's Manual) and the
/// README says so. Used by CueScheduler (Vardaan's module).
enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case new
    case gettingComfortable
    case nearlyLicensed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: "New"
        case .gettingComfortable: "Getting comfortable"
        case .nearlyLicensed: "Nearly licensed"
        }
    }

    var summary: String {
        switch self {
        case .new: "First weeks on a permit. Lane cues 3/4 mile early, every light counted, stop signs called."
        case .gettingComfortable: "Most of the 50 hours. Lane cues half a mile early, the last two lights counted."
        case .nearlyLicensed: "Test prep. Cues timed like a regular maps app, crash corridors only."
        }
    }

    /// How far before a turn or roundabout the lane cue fires on roads posted 40 mph or more.
    var laneLeadFastMeters: Double {
        switch self {
        case .new: 1200            // about 0.75 mi
        case .gettingComfortable: 800   // about 0.5 mi
        case .nearlyLicensed: 480   // about 0.3 mi
        }
    }

    /// Same, on roads posted under 40 mph.
    var laneLeadSlowMeters: Double {
        switch self {
        case .new: 650
        case .gettingComfortable: 400
        case .nearlyLicensed: 250
        }
    }

    /// How many of the lights before a maneuver are counted down aloud. Int.max means every one.
    var countdownLights: Int {
        switch self {
        case .new: Int.max
        case .gettingComfortable: 2
        case .nearlyLicensed: 1
        }
    }

    var speaksSpeedChanges: Bool { self != .nearlyLicensed }
    var speaksSchoolZones: Bool { self != .nearlyLicensed }
    var speaksStopSigns: Bool { self == .new }
}
