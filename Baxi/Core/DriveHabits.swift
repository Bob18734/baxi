import Foundation

/// The car's speed at one location fix, where it was along the route, and the posted limit there.
struct SpeedSample: Codable, Equatable {
    let t: TimeInterval
    let along: Double
    /// Meters per second from the GPS; negative when the phone did not know.
    let mps: Double
    let limitMph: Int?
}

/// How a drive went, for the coaching card after it and the trend in the Log.
struct HabitReport: Codable, Equatable {
    var trackedMinutes: Double
    /// Share of the time on roads with a known limit spent more than 5 mph over it. nil when no limit was known.
    var overLimitShare: Double?
    /// The most over the limit, in mph; nil when never more than 5 over.
    var topOverMph: Int?
    /// Top speed inside a school zone; nil when the drive passed none.
    var schoolZoneTopMph: Int?
    var stopSigns: Int
    var fullStops: Int
    var hardBrakes: Int
    var merges: Int
    var mergesUpToSpeed: Int
    /// 0 to 100.
    var score: Int
    /// A replay of the route, not a real drive.
    var isDemo: Bool

    var rollingStops: Int { stopSigns - fullStops }
    var slowMerges: Int { merges - mergesUpToSpeed }
}

/// Turns a drive's speed samples into habits a new driver can work on. All of the numbers are Baxi's own
/// coaching choices, not Indiana law (the README says so).
enum DriveHabits {
    static let mphPerMps = 2.23694
    /// More than this over the posted limit counts as over.
    static let overMph = 5.0
    /// Below this the car has stopped (about 3 mph: GPS speed is rarely exactly zero).
    static let stoppedMps = 1.3
    /// A stop sign's stop is looked for from this far before it to `stopAfterMeters` past it.
    static let stopBeforeMeters = 25.0, stopAfterMeters = 10.0
    /// Slowing faster than this (about 0.35 g) from above 10 mph is a hard brake.
    static let hardBrakeMps2 = 3.4, hardBrakeFromMps = 4.5
    /// Hard decelerations closer together than this are one event.
    static let hardBrakeGapSeconds = 5.0
    /// A merge is judged this far past the merge point: speed within 10 mph of the limit (45 mph where unknown).
    static let mergeCheckMeters = 150.0, mergeUnderLimitMph = 10.0, mergeDefaultMph = 45.0
    /// Fixes further apart than this are a GPS gap, not driving time.
    static let maxGapSeconds = 10.0
    /// Shorter drives get no report.
    static let minTrackedMinutes = 2.0
    static let schoolZoneMph = 20

    /// Whole miles per hour, as a speedometer shows them (so 40.0000001 is not "over 40").
    static func mph(_ x: SpeedSample) -> Double { (x.mps * mphPerMps).rounded() }

    static func report(samples raw: [SpeedSample], stopSignAlongs: [Double], schoolZones: [ClosedRange<Double>],
                       mergeAlongs: [Double], isDemo: Bool) -> HabitReport? {
        let s = raw.filter { $0.mps >= 0 }.sorted { $0.t < $1.t }
        var tracked = 0.0, knownLimit = 0.0, over = 0.0
        var hardBrakes = 0, lastBrake = -Double.infinity
        for (a, b) in zip(s, s.dropFirst()) {
            let dt = b.t - a.t
            guard dt > 0, dt <= maxGapSeconds else { continue }
            tracked += dt
            if let limit = a.limitMph {
                knownLimit += dt
                if mph(a) > Double(limit) + overMph { over += dt }
            }
            if dt >= 0.5, a.mps > hardBrakeFromMps, (a.mps - b.mps) / dt > hardBrakeMps2 {
                if b.t - lastBrake >= hardBrakeGapSeconds { hardBrakes += 1 }
                lastBrake = b.t
            }
        }
        guard tracked / 60 >= minTrackedMinutes else { return nil }

        let topOver = s.compactMap { x in x.limitMph.map { mph(x) - Double($0) } }.max()
            .flatMap { $0 > overMph ? Int($0.rounded()) : nil }
        let schoolTop = s.filter { x in schoolZones.contains { $0.contains(x.along) } }.map(mph).max().map { Int($0) }

        var stopSigns = 0, fullStops = 0
        for sign in stopSignAlongs {
            let near = s.filter { $0.along >= sign - stopBeforeMeters && $0.along <= sign + stopAfterMeters }
            guard let slowest = near.map(\.mps).min() else { continue }   // not driven, or no fix there
            stopSigns += 1
            if slowest < stoppedMps { fullStops += 1 }
        }

        var merges = 0, upToSpeed = 0
        for m in mergeAlongs {
            let target = m + mergeCheckMeters
            guard let x = s.min(by: { abs($0.along - target) < abs($1.along - target) }), abs(x.along - target) <= 40 else { continue }
            merges += 1
            let needed = x.limitMph.map { Double($0) - mergeUnderLimitMph } ?? mergeDefaultMph
            if mph(x) >= needed { upToSpeed += 1 }
        }

        let share: Double? = knownLimit > 0 ? over / knownLimit : nil
        var score = 100.0 - min(30, (share ?? 0) * 100)
        score -= Double(8 * (stopSigns - fullStops) + 6 * hardBrakes + 5 * (merges - upToSpeed))
        if let schoolTop, schoolTop > schoolZoneMph { score -= 10 }
        return HabitReport(trackedMinutes: tracked / 60, overLimitShare: share, topOverMph: topOver, schoolZoneTopMph: schoolTop,
                           stopSigns: stopSigns, fullStops: fullStops, hardBrakes: hardBrakes, merges: merges,
                           mergesUpToSpeed: upToSpeed, score: max(0, Int(score.rounded())), isDemo: isDemo)
    }

    /// Up to three things to work on, most important first: school zones, speed, stop signs, braking, merges.
    static func tips(_ r: HabitReport) -> [String] {
        var out: [String] = []
        if let top = r.schoolZoneTopMph, top > schoolZoneMph {
            out.append("Top speed in a school zone was \(top) mph. School zones are \(schoolZoneMph) when the lights flash.")
        }
        if let share = r.overLimitShare, share >= 0.01, let top = r.topOverMph {
            out.append("Over the limit for \(max(1, Int((share * 100).rounded())))% of the drive, by up to \(top) mph. Ease off a little.")
        }
        if r.rollingStops > 0 {
            out.append("\(r.rollingStops) of \(r.stopSigns) stop signs \(r.rollingStops == 1 ? "was a rolling stop" : "were rolling stops"). "
                       + "Come to a full stop and count to two.")
        }
        if r.hardBrakes > 0 {
            out.append(r.hardBrakes == 1 ? "One hard stop. Look further ahead and brake earlier."
                                         : "\(r.hardBrakes) hard stops. Look further ahead and brake earlier.")
        }
        if r.slowMerges > 0 { out.append("Merge at highway speed: speed up on the ramp before you join.") }
        return out.isEmpty ? ["Clean drive. Keep it up."] : Array(out.prefix(3))
    }

    // Stored on DriveRecord as JSON text, so records saved before Oct 24 (empty) still load.
    static func encode(_ r: HabitReport?) -> String {
        guard let r, let d = try? JSONEncoder().encode(r) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }

    static func decode(_ s: String) -> HabitReport? {
        guard !s.isEmpty, let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HabitReport.self, from: d)
    }
}
