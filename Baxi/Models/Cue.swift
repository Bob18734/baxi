import Foundation

/// What a cue is about. Also its priority when two are due at once (first is highest).
enum CueKind: String, Codable, CaseIterable {
    case turn
    case roundabout
    case laneChange
    case ramp
    case crashCorridor
    case speedChange
    case schoolZone
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

    /// Fills the placeholders. `lights` is the number of signals between the driver and the
    /// maneuver this cue sets up, counted at fire time by the Drive screen.
    /// {lightsClause} becomes ", your turn is in 2 lights" or nothing; {lights} becomes "2 lights".
    /// A signal cue with 0 lights left means the turn is at this light.
    func spoken(lights: Int?) -> String { Self.fill(spokenTemplate, kind: kind, lights: lights) }
    func card(lights: Int?) -> String { Self.fill(cardTemplate, kind: kind, lights: lights) }

    static func fill(_ s: String, kind: CueKind, lights: Int?) -> String {
        if kind == .signal, lights == 0 { return s.contains("{lights}") ? "Your turn is at this light" : s }
        let word = lights.map { $0 == 1 ? "1 light" : "\($0) lights" }
        return s.replacingOccurrences(of: "{lightsClause}", with: word.map { ", your turn is in \($0)" } ?? "")
                .replacingOccurrences(of: "{lights}", with: word ?? "")
    }
}
