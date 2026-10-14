import Foundation

/// What a cue is about. Also its priority when two are due at once (first is highest).
enum CueKind: String, Codable, CaseIterable {
    case turn
    case roundabout
    case laneChange
    case ramp
    case railroad
    case crashCorridor
    case speedChange
    case schoolZone
    case glare
    case signal
    case stopSign
    case arrive

    var priority: Int { CueKind.allCases.firstIndex(of: self) ?? 99 }
}

/// Which lanes to light up on the strip across the top of the Drive screen.
struct LaneStrip: Codable, Equatable {
    let laneCount: Int
    /// Zero-based from the left.
    let highlighted: [Int]
    /// One short label per lane, such as "←", "↑", "→", "↑→", or "" when unknown.
    let labels: [String]
}

/// One thing the app will say and show, placed by meters along the route.
/// CueListBuilder makes these; CueScheduler (Vardaan's module) decides when each one fires.
struct Cue: Identifiable, Codable, Equatable {
    let id: String
    let kind: CueKind
    /// Where the thing itself is: the turn, the light, the speed sign.
    let targetMeters: Double
    /// Spoken once. May contain {lights}, replaced at fire time with the number of lights to the maneuver.
    let spokenTemplate: String
    /// Shown on the card. Same placeholder rule.
    let cardTemplate: String
    let laneStrip: LaneStrip?
    /// Posted speed at the target, used to pick the lead distance.
    let roadSpeedMph: Int?
    /// The maneuver this cue sets up, when any. Signals count toward the next such maneuver.
    let maneuverId: Int?
    /// Set by CueScheduler.plan. nil means this cue never fires at this experience level.
    var fireAtMeters: Double? = nil

    /// Fills the placeholders, as a co-pilot would say it:
    /// - {in}: "In a quarter mile, " from `metersAway` (nothing when it is right there or unknown);
    /// - {ahead}: ", half a mile ahead" for lane cues with no light count;
    /// - {lightsClause}: ". It's at the second light" (the turn's own light counted);
    /// - {lights}: a signal cue's countdown, "Two more lights", "One more light", or the last light;
    /// - {reminder}: said once per drive by DriveSession, left out everywhere else.
    /// The first letter is capitalized after filling.
    func spoken(lights: Int?, metersAway: Double? = nil) -> String {
        Self.fill(spokenTemplate, kind: kind, lights: lights, metersAway: metersAway)
    }
    func card(lights: Int?) -> String { Self.fill(cardTemplate, kind: kind, lights: lights, metersAway: nil) }

    static func fill(_ s: String, kind: CueKind, lights: Int?, metersAway: Double?) -> String {
        let distance = metersAway.flatMap(distancePhrase)
        var out = s.replacingOccurrences(of: "{in}", with: distance.map { "In \($0), " } ?? "")
            .replacingOccurrences(of: "{reminder}", with: "")
        if let lights, lights > 0 {
            out = out.replacingOccurrences(of: "{lightsClause}", with: ". It's at the \(ordinalWord(lights)) light")
                .replacingOccurrences(of: "{ahead}", with: "")
        } else {
            out = out.replacingOccurrences(of: "{lightsClause}", with: "")
                .replacingOccurrences(of: "{ahead}", with: distance.map { ", \($0) ahead" } ?? "")
        }
        if kind == .signal {
            let countdown: String
            switch lights ?? 0 {
            case 0: countdown = "That's the last light. Your turn is next"
            case 1: countdown = "One more light"
            case let n: countdown = "\(n) more lights"
            }
            out = out.replacingOccurrences(of: "{lights}", with: countdown)
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    /// Distances the way people say them: "500 feet", "a quarter mile", "half a mile". nil under 100 m,
    /// where the instruction is simply now.
    static func distancePhrase(_ meters: Double) -> String? {
        guard meters >= 100 else { return nil }
        let marks: [(Double, String)] = [(152, "500 feet"), (305, "1,000 feet"), (402, "a quarter mile"), (805, "half a mile"),
                                         (1_207, "three quarters of a mile"), (1_609, "a mile"), (3_219, "2 miles")]
        return marks.min { abs(log(meters / $0.0)) < abs(log(meters / $1.0)) }?.1
    }

    static func ordinalWord(_ n: Int) -> String {
        ["first", "second", "third", "fourth", "fifth", "sixth"].indices.contains(n - 1)
            ? ["first", "second", "third", "fourth", "fifth", "sixth"][n - 1] : "\(n)th"
    }
}
