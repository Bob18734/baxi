import Foundation

/// Where the car is on the route, as meters along the line. Fed one location fix at a time.
/// Progress only moves forward, so a GPS wobble never "un-passes" a cue, and a car more than
/// 60 m off the line for 10 s is reported off route (the Drive screen then says so).
struct RouteProgress: Equatable {
    let alongMeters: Double
    let crossTrackMeters: Double
    let segmentIndex: Int
    let snapped: Coordinate
    let remainingMeters: Double
    let isOffRoute: Bool
}

final class RouteFollower {
    static let offRouteMeters = 60.0
    static let offRouteSeconds: TimeInterval = 10

    let polyline: Polyline
    private(set) var alongMeters = 0.0
    private(set) var lastSegment: Int?
    private var offRouteSince: TimeInterval?
    private(set) var isOffRoute = false

    init(polyline: Polyline) { self.polyline = polyline }

    func update(location: Coordinate, at time: TimeInterval) -> RouteProgress? {
        // Near the last known segment while on route; the whole line when lost or at the start.
        var proj = polyline.project(location, near: isOffRoute ? nil : lastSegment)
        guard var p = proj else { return nil }

        if p.crossTrackMeters > Self.offRouteMeters {
            // Maybe the window was wrong (a loop route passes near itself). Try the whole line once.
            if lastSegment != nil, let global = polyline.project(location), global.crossTrackMeters <= Self.offRouteMeters,
               global.alongMeters >= alongMeters - Self.offRouteMeters {
                p = global; proj = global
            } else {
                if offRouteSince == nil { offRouteSince = time }
                if time - (offRouteSince ?? time) >= Self.offRouteSeconds { isOffRoute = true }
                return RouteProgress(alongMeters: alongMeters, crossTrackMeters: p.crossTrackMeters,
                                     segmentIndex: lastSegment ?? p.segmentIndex, snapped: p.point,
                                     remainingMeters: polyline.lengthMeters - alongMeters, isOffRoute: isOffRoute)
            }
        }

        // Back on the line.
        offRouteSince = nil
        let wasOffRoute = isOffRoute
        isOffRoute = false
        // Forward only, unless we just re-found the route somewhere else.
        alongMeters = wasOffRoute ? p.alongMeters : max(alongMeters, p.alongMeters)
        lastSegment = p.segmentIndex
        return RouteProgress(alongMeters: alongMeters, crossTrackMeters: p.crossTrackMeters,
                             segmentIndex: p.segmentIndex, snapped: p.point,
                             remainingMeters: max(0, polyline.lengthMeters - alongMeters), isOffRoute: false)
    }
}
