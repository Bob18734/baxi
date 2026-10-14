import Foundation

/// Sunrise and sunset from the standard sunrise equation (NOAA's simplified solar position), and the
/// day and night split of a drive. Baxi counts night as sunset to sunrise. Indiana's statute
/// (IC 9-24-3-2.5) requires 10 night hours but does not define night, so this boundary is our choice.
enum Daylight {
    /// Sunrise and sunset for the local calendar day that contains `date`. nil during polar day or night.
    static func sunriseSunset(on date: Date, at c: Coordinate, timeZone: TimeZone = .current) -> (sunrise: Date, sunset: Date)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        guard let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) else { return nil }

        let rad = Double.pi / 180
        let jd = noon.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let n = (jd - 2_451_545.0 + 0.0008).rounded()
        let jStar = n - c.lon / 360
        let m = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360)
        let center = 1.9148 * sin(m * rad) + 0.0200 * sin(2 * m * rad) + 0.0003 * sin(3 * m * rad)
        let lambda = (m + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = 2_451_545.0 + jStar + 0.0053 * sin(m * rad) - 0.0069 * sin(2 * lambda * rad)
        let sinDec = sin(lambda * rad) * sin(23.4397 * rad)
        let cosDec = cos(asin(sinDec))
        let cosOmega = (sin(-0.833 * rad) - sin(c.lat * rad) * sinDec) / (cos(c.lat * rad) * cosDec)
        guard abs(cosOmega) <= 1 else { return nil }
        let omega = acos(cosOmega) / rad

        func fromJulian(_ julian: Double) -> Date { Date(timeIntervalSince1970: (julian - 2_440_587.5) * 86_400) }
        return (fromJulian(transit - omega / 360), fromJulian(transit + omega / 360))
    }

    /// Splits a drive into whole day and night minutes. Each minute counts by its midpoint.
    static func split(start: Date, end: Date, at c: Coordinate, timeZone: TimeZone = .current) -> (day: Int, night: Int) {
        let total = Int((end.timeIntervalSince(start) / 60).rounded())
        guard total > 0 else { return (0, 0) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var byDay: [Date: (sunrise: Date, sunset: Date)?] = [:]
        var day = 0
        for i in 0..<total {
            let t = start.addingTimeInterval(Double(i) * 60 + 30)
            let key = cal.startOfDay(for: t)
            if byDay[key] == nil { byDay[key] = .some(sunriseSunset(on: t, at: c, timeZone: timeZone)) }
            if let s = byDay[key] ?? nil, t >= s.sunrise && t < s.sunset { day += 1 }
        }
        return (day, total - day)
    }
}
