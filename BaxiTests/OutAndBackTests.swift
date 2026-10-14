import Foundation
import Testing
@testable import Baxi

/// The roundabout loop drives the same stretch out and back. Before the fix, the follower snapped
/// to the later pass and skipped 600 m of cues at once.
struct OutAndBackTests {
    @Test(arguments: ["preset_roundabouts", "preset_parkway", "preset_highway"])
    func progressNeverJumpsAhead(_ id: String) throws {
        let route = try RouteService.preset(id)
        var follower = RouteFollower(polyline: route.polyline)
        var last = 0.0, t = 0.0, m = 0.0
        while m < route.polyline.lengthMeters {
            m += 5; t += 1
            guard let c = route.polyline.coordinate(atMeters: m), let p = follower.update(location: c, at: t) else { continue }
            #expect(p.alongMeters - last < 50, "jumped from \(Int(last)) m to \(Int(p.alongMeters)) m at \(Int(m)) m")
            #expect(abs(p.alongMeters - m) < 50, "at \(Int(m)) m the follower thinks \(Int(p.alongMeters)) m")
            last = p.alongMeters
        }
    }
}
