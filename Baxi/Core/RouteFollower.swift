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
    /// The fix matched far ahead and is waiting for the next one to confirm it; progress did not move.
    /// The drive treats it as if it never came.
    var isHeld = false
}

final class RouteFollower {
    static let offRouteMeters = 60.0
    static let offRouteSeconds: TimeInterval = 10

    let polyline: Polyline
    private(set) var alongMeters = 0.0
    private(set) var lastSegment: Int?
    private var offRouteSince: TimeInterval?
    private(set) var isOffRoute = false
    /// The last fix that moved the car along the line.
    private var lastOnLineTime: TimeInterval?
    /// A far-ahead match seen once, waiting for the next fix to confirm it.
    private var pendingJump: (along: Double, time: TimeInterval)?
    /// Further along than this in one step needs a second fix to agree.
    static let confirmJumpMeters = 250.0
    /// A fix this much closer to the other stretch than to the current one counts as being on the other stretch.
    static let clearlyOtherMeters = 20.0
    /// How far a confirming fix may have moved on from the first (about 100 mph per second, plus GPS error).
    static let maxPlausibleMps = 45.0

    init(polyline: Polyline) { self.polyline = polyline }

    func update(location: Coordinate, at time: TimeInterval) -> RouteProgress? {
        // Near the last known segment while on route; the whole line when lost or at the start.
        var proj: Polyline.Projection?
        if lastSegment == nil, !isOffRoute, let start = polyline.project(location, expectedAlong: 0, tolerance: 300),
           start.crossTrackMeters <= Self.offRouteMeters {
            // First fix: prefer the start. A loop ends where it begins, so a whole-line search
            // could snap to the last segment and finish the drive at once.
            proj = start
        } else {
            proj = polyline.project(location, near: isOffRoute ? nil : lastSegment, fromAlong: lastSegment == nil ? nil : alongMeters)
        }
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

        // Far further along in one step (a bad fix on a parallel street, a GPS jump): hold where the car was
        // until the next fix confirms it.
        var keepPending = false
        if lastOnLineTime != nil, p.alongMeters - alongMeters > Self.confirmJumpMeters,
           let here = polyline.project(location, expectedAlong: alongMeters, tolerance: Self.confirmJumpMeters),
           here.crossTrackMeters <= Self.offRouteMeters {
            // Still within GPS error of the street the car is on: stay on it, even if a later stretch of the
            // route (a parallel street) happens to be closer to this fix. Unless fixes keep landing clearly on
            // that other stretch: two that agree mean the car really is there (a turnaround on a divided road).
            let far = p
            if here.crossTrackMeters - far.crossTrackMeters > Self.clearlyOtherMeters, confirmsJump(to: far.alongMeters, at: time) {
                p = far
            } else {
                p = here
                keepPending = true
            }
        }
        if lastOnLineTime != nil, !confirmsJump(to: p.alongMeters, at: time) {
            let here = polyline.project(location, expectedAlong: alongMeters, tolerance: 250)
            return RouteProgress(alongMeters: alongMeters, crossTrackMeters: here?.crossTrackMeters ?? p.crossTrackMeters,
                                 segmentIndex: lastSegment ?? p.segmentIndex, snapped: here?.point ?? p.point,
                                 remainingMeters: max(0, polyline.lengthMeters - alongMeters), isOffRoute: isOffRoute,
                                 isHeld: true)
        }

        // Back on the line.
        lastOnLineTime = time
        if !keepPending { pendingJump = nil }
        offRouteSince = nil
        isOffRoute = false
        // Returning behind the previous fix must not rewind distance or re-count maneuvers.
        // A newly installed route gets its own follower and starts its own progress at zero.
        alongMeters = max(alongMeters, p.alongMeters)
        lastSegment = p.segmentIndex
        return RouteProgress(alongMeters: alongMeters, crossTrackMeters: p.crossTrackMeters,
                             segmentIndex: p.segmentIndex, snapped: p.point,
                             remainingMeters: max(0, polyline.lengthMeters - alongMeters), isOffRoute: false)
    }

    /// A match more than `confirmJumpMeters` further along between fixes a second apart is believed only when the
    /// next fix agrees: one bad fix on a parallel street must not skip the turns in between. A real jump is
    /// followed one fix later.
    private func confirmsJump(to along: Double, at time: TimeInterval) -> Bool {
        let jump = along - alongMeters
        if jump <= Self.confirmJumpMeters { return true }
        // After a real dropout (a few seconds with no fix on the line), any distance the car could have driven
        // in that time is believed at once.
        let gap = time - (lastOnLineTime ?? time)
        if gap >= 3, jump <= Self.maxPlausibleMps * gap + Self.offRouteMeters { return true }
        if let pending = pendingJump, along >= pending.along - Self.offRouteMeters,
           along - pending.along <= Self.maxPlausibleMps * max(1, time - pending.time) + Self.offRouteMeters {
            return true
        }
        pendingJump = (along, time)
        return false
    }
}
