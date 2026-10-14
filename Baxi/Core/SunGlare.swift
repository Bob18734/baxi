import Foundation

/// Where the sun is in the sky, from the NOAA solar position equations (accurate to about a degree,
/// plenty for "is the sun low and ahead").
enum SolarPosition {
    /// Azimuth (degrees clockwise from north) and altitude (degrees above the horizon).
    static func at(_ date: Date, _ c: Coordinate) -> (azimuth: Double, altitude: Double) {
        let rad = Double.pi / 180
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (jd - 2_451_545.0) / 36_525
        let l0 = (280.46646 + t * (36_000.76983 + 0.0003032 * t)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let center = sin(m * rad) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * m * rad) * (0.019993 - 0.000101 * t)
            + sin(3 * m * rad) * 0.000289
        let omega = 125.04 - 1934.136 * t
        let lambda = l0 + center - 0.00569 - 0.00478 * sin(omega * rad)
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(omega * rad)
        let decl = asin(sin(eps * rad) * sin(lambda * rad))
        let y = pow(tan(eps * rad / 2), 2)
        let eqTime = 4 / rad * (y * sin(2 * l0 * rad) - 2 * e * sin(m * rad) + 4 * e * y * sin(m * rad) * cos(2 * l0 * rad)
            - 0.5 * y * y * sin(4 * l0 * rad) - 1.25 * e * e * sin(2 * m * rad))
        let utcMinutes = (jd + 0.5).truncatingRemainder(dividingBy: 1) * 1_440
        let trueSolar = (utcMinutes + eqTime + 4 * c.lon).truncatingRemainder(dividingBy: 1_440)
        let hourAngle = (trueSolar / 4 < 0 ? trueSolar / 4 + 180 : trueSolar / 4 - 180) * rad
        let lat = c.lat * rad
        let zenith = acos(max(-1, min(1, sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle))))
        let az = atan2(sin(hourAngle), cos(hourAngle) * sin(lat) - tan(decl) * cos(lat)) / rad + 180
        return ((az + 360).truncatingRemainder(dividingBy: 360), 90 - zenith / rad)
    }
}

/// Stretches of a route that point into a low sun at the time they will be driven: glare can hide
/// traffic lights, signs and brake lights. Worked out from the sun's position, no data needed.
enum SunGlare {
    /// The sun is "low" from the horizon to this many degrees up.
    static let maxAltitude = 15.0
    /// And "ahead" within this many degrees either side of the direction of travel.
    static let maxOffAxis = 25.0
    static let minimumStretchMeters = 150.0

    struct Stretch: Equatable { let startMeters: Double; let endMeters: Double }

    /// Glare stretches when the drive starts at `start`, assuming it takes the route's usual time.
    static func stretches(route: PlannedRoute, start: Date, from fromMeters: Double = 0) -> [Stretch] {
        let line = route.polyline
        guard line.lengthMeters > 0 else { return [] }
        let speed = route.durationSeconds > 0 ? line.lengthMeters / route.durationSeconds : 12
        var out: [Stretch] = [], runStart: Double?
        var m = fromMeters
        while m <= line.lengthMeters {
            var glare = false
            if let c = line.coordinate(atMeters: m), let heading = line.bearing(atMeters: m) {
                let sun = SolarPosition.at(start.addingTimeInterval((m - fromMeters) / speed), c)
                let off = abs(((sun.azimuth - heading) + 540).truncatingRemainder(dividingBy: 360) - 180)
                glare = sun.altitude > 0 && sun.altitude <= maxAltitude && off <= maxOffAxis
            }
            if glare, runStart == nil { runStart = m }
            if !glare, let s = runStart {
                if m - s >= minimumStretchMeters { out.append(Stretch(startMeters: s, endMeters: m)) }
                runStart = nil
            }
            m += 50
        }
        if let s = runStart, line.lengthMeters - s >= minimumStretchMeters { out.append(Stretch(startMeters: s, endMeters: line.lengthMeters)) }
        return out
    }

    static func cues(_ stretches: [Stretch], speeds: [(along: Double, mph: Int)]) -> [Cue] {
        stretches.map { s in
            Cue(id: "glare-\(Int(s.startMeters))", kind: .glare, targetMeters: s.startMeters,
                spokenTemplate: "Low sun ahead. Traffic lights and brake lights may be hard to see",
                cardTemplate: "Low sun ahead", laneStrip: nil,
                roadSpeedMph: CueListBuilder.speed(at: s.startMeters, in: speeds), maneuverId: nil)
        }
    }
}
