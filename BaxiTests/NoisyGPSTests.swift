import Foundation
import Testing
@testable import Baxi

private final class Quiet: SpeechOutput {
    var isMuted = false
    func say(_ text: String) {}
    func stop() {}
}

/// Deterministic random numbers, so a failure reproduces exactly.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// Standard normal, Box-Muller.
    mutating func gaussian() -> Double {
        let u = max(Double.random(in: 0..<1, using: &self), 1e-12), v = Double.random(in: 0..<1, using: &self)
        return sqrt(-2 * log(u)) * cos(2 * .pi * v)
    }
}

/// A phone's view of a drive: one fix a second, position error that drifts the way real GPS does,
/// waits at lights, and dropouts. Used to check that real-world GPS does not change what Baxi says.
struct GPSSimulator {
    var errorMeters = 8.0
    var stopSecondsAtLights = 45.0
    var dropoutEveryMeters = 3_000.0
    var dropoutSeconds = 15.0
    /// Chance per fix of a one-off jump (a reflection off a building), and its size.
    var outlierChance = 0.0
    var outlierMeters = 40.0
    var seed: UInt64 = 1

    struct Fix { let coordinate: Coordinate; let time: TimeInterval }

    func fixes(for route: PlannedRoute, lights: [Double]) -> [Fix] {
        var rng = SplitMix(state: seed)
        let line = route.polyline
        var out: [Fix] = []
        var meters = 0.0, t = 0.0
        var ex = 0.0, ny = 0.0                 // correlated error east and north, meters
        var pendingLights = lights.sorted()
        var nextDropout = dropoutEveryMeters
        var dropoutUntil = -1.0
        func emit(_ m: Double) {
            // AR(1): each second keeps 85% of the last error, so it wanders instead of jumping.
            let k = 0.85, s = errorMeters * sqrt(1 - k * k)
            ex = k * ex + s * rng.gaussian(); ny = k * ny + s * rng.gaussian()
            guard t >= dropoutUntil, let c = line.coordinate(atMeters: m) else { return }
            var e = ex, n = ny
            if Double.random(in: 0..<1, using: &rng) < outlierChance {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                e += outlierMeters * cos(a); n += outlierMeters * sin(a)
            }
            out.append(Fix(coordinate: Self.offset(c, east: e, north: n), time: t))
        }
        while meters < line.lengthMeters {
            let nearTurn = route.maneuvers.contains { $0.needsLaneChoice && abs($0.alongMeters - meters) < 60 }
            let speed = nearTurn ? 6.7 : 13.4      // 15 mph at turns and roundabouts, 30 mph otherwise
            meters = min(line.lengthMeters, meters + speed)
            t += 1
            if let light = pendingLights.first, meters >= light - 5 {
                pendingLights.removeFirst()
                for _ in 0..<Int(stopSecondsAtLights) { emit(meters); t += 1 }   // stopped, still jittering
            }
            if meters >= nextDropout { dropoutUntil = t + dropoutSeconds; nextDropout += dropoutEveryMeters }
            emit(meters)
        }
        for _ in 0..<60 { t += 1; emit(line.lengthMeters) }         // parked at the end for a minute
        return out
    }

    static func offset(_ c: Coordinate, east: Double, north: Double) -> Coordinate {
        let ky = 111_195.0, kx = ky * cos(c.lat * .pi / 180)
        return Coordinate(lat: c.lat + north / ky, lon: c.lon + east / kx)
    }
}

struct NoisyGPSTests {
    static let cache = try! BundledData.carmelCache()
    static let features = FeatureExtractor.extract(from: cache)

    func session(_ route: PlannedRoute, mode: DriveSession.Mode) -> DriveSession {
        DriveSession(route: route, cache: Self.cache, features: Self.features, highInjury: nil, level: .gettingComfortable,
                     mode: mode, speaker: Quiet())
    }

    @Test(arguments: ["preset_roundabouts", "preset_parkway", "preset_highway", "preset_firstdrive", "preset_downtown"], [UInt64(1), 2, 3])
    func realisticGPSSaysTheSameThingsInTheSameOrder(_ id: String, seed: UInt64) throws {
        try check(id, GPSSimulator(seed: seed))
    }

    /// Bad GPS: twice the drift, 30 s dropouts, and a 40 m jump on one fix in fifty.
    @Test(arguments: ["preset_roundabouts", "preset_parkway", "preset_highway", "preset_firstdrive", "preset_downtown"], [UInt64(11), 12, 13])
    func badGPSStillSaysTheSameThings(_ id: String, seed: UInt64) throws {
        try check(id, GPSSimulator(errorMeters: 15, dropoutSeconds: 30, outlierChance: 0.02, seed: seed))
    }

    func check(_ id: String, _ gps: GPSSimulator) throws {
        let route = try RouteService.preset(id)
        let cleanLog = session(route, mode: .replay(speedMultiplier: 1)).simulateWholeRoute()
        let clean = cleanLog.map(\.text)

        let s = session(route, mode: .live)
        let lights = CueListBuilder.signalAlongs(line: route.polyline, cache: Self.cache)
        for f in gps.fixes(for: route, lights: lights) { s.feed(f.coordinate, at: f.time) }
        let noisy = s.spokenLog.map(\.text)

        #expect(s.isFinished, "the drive never ended")
        #expect(!noisy.contains { $0.contains("Off the route") }, "GPS noise read as leaving the route")
        #expect(s.rerouteCount == 0)
        #expect(abs(s.drivenMeters - route.polyline.lengthMeters) / route.polyline.lengthMeters < 0.01,
                "logged \(Int(s.drivenMeters)) m of \(Int(route.polyline.lengthMeters)) m")
        // Driving instructions (turns, roundabouts, lanes, ramps, merges, arrival) in exactly the same order.
        // Everything else (speed limits, school zones, stop signs) must all be said, in any order: when one
        // comes due with a maneuver, which goes first depends on the second each fix lands.
        // Light countdowns and the "destination is just ahead" heads-up depend on timing and are left out:
        // a car stopped at a light has time for a countdown a car rolling through does not.
        // A turn inside the arrival radius (within 30 m of the end) may be overtaken by "You've arrived": which
        // comes first depends on where the last fixes land.
        let finalTurns = Set(cleanLog.filter { $0.text != "You've arrived" && route.polyline.lengthMeters - $0.meters < 2 * DriveSession.arrivalMeters }
            .map(\.text))
        func optional(_ s: String) -> Bool { s.hasSuffix("more lights") || s == "One more light" || s.hasPrefix("That's the last light") || s.hasPrefix("Your destination") || finalTurns.contains(s) }
        func isAdvisory(_ s: String) -> Bool { s.hasPrefix("Speed limit") || s.hasPrefix("School zone") || s.hasPrefix("Stop sign") || s.hasPrefix("Crash-heavy") }
        // "In a quarter mile" versus "In 1,000 feet" depends on exactly where a fix lands, so the distance
        // phrase is set aside; the instruction itself must match word for word.
        func instruction(_ s: String) -> String {
            let d = "(500 feet|1,000 feet|a quarter mile|half a mile|three quarters of a mile|a mile|2 miles)"
            let t = s.replacingOccurrences(of: "^In \(d), ", with: "", options: .regularExpression)
                .replacingOccurrences(of: ", \(d) ahead$", with: "", options: .regularExpression)
            return t.prefix(1).uppercased() + t.dropFirst()
        }
        let must = noisy.filter { !optional($0) && !isAdvisory($0) }.map(instruction)
        let expected = clean.filter { !optional($0) && !isAdvisory($0) }.map(instruction)
        #expect(must == expected, "\(zip(must, expected).first { $0 != $1 }.map { "noisy: \($0.0)\nclean: \($0.1)" } ?? "lengths \(must.count) vs \(expected.count)")")
        #expect(noisy.filter(isAdvisory).sorted() == clean.filter(isAdvisory).sorted())
    }
}
