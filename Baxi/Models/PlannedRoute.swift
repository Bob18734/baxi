import Foundation

/// One step of the route as the router describes it (OSRM, or Apple directions as the fallback).
struct Maneuver: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case depart, turn, roundabout, merge, onRamp, offRamp, fork, continueStraight, arrive, other
    }
    enum Direction: String, Codable {
        case left, right, slightLeft, slightRight, sharpLeft, sharpRight, straight, uturn
    }

    let id: Int
    let kind: Kind
    let direction: Direction?
    let location: Coordinate
    /// Meters from the route start to this maneuver.
    let alongMeters: Double
    /// Roundabouts only: which exit to take, counting from 1.
    let exitNumber: Int?
    /// The road the maneuver turns onto, when the router names it.
    let roadName: String?
    /// The router's own sentence, kept for debugging and as the last-resort card text.
    let instruction: String
    /// Lane data the router attaches to the intersection, when it has any: total lanes and the
    /// zero-based indexes (from the left) that are valid for this maneuver.
    let laneCount: Int?
    let validLanes: [Int]?

    /// True for the maneuvers a driver has to set up for: turns and roundabout exits.
    var needsLaneChoice: Bool {
        switch kind {
        case .turn, .roundabout, .offRamp, .fork: true
        default: false
        }
    }
}

/// A routed trip: the line, the maneuvers on it, and where it came from.
struct PlannedRoute: Identifiable, Equatable {
    let id: String
    let name: String
    let polyline: Polyline
    let maneuvers: [Maneuver]
    let distanceMeters: Double
    let durationSeconds: Double
    /// "osrm", "apple", or "preset".
    let source: String
}
