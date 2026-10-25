import Foundation

/// One row of the supervised driving log, as plain values so totals and exports are testable
/// without SwiftData.
struct LogRow: Equatable {
    let start: Date
    let end: Date
    let dayMinutes: Int
    let nightMinutes: Int
    let routeTitle: String
    let distanceMeters: Double
    let manual: Bool
    /// The stored drive this row came from, so an edit is not compared with itself.
    var id: UUID? = nil

    var minutes: Int { dayMinutes + nightMinutes }
}

/// Totals toward Indiana's requirement and the CSV export.
enum DriveLog {
    /// IC 9-24-3-2.5: at least 50 hours of supervised practice, at least 10 of them at night.
    static let requiredMinutes = 50 * 60
    static let requiredNightMinutes = 10 * 60

    struct Totals: Equatable {
        let minutes: Int
        let nightMinutes: Int
        var dayMinutes: Int { minutes - nightMinutes }
        var minutesLeft: Int { max(0, DriveLog.requiredMinutes - minutes) }
        var nightMinutesLeft: Int { max(0, DriveLog.requiredNightMinutes - nightMinutes) }
        var isComplete: Bool { minutesLeft == 0 && nightMinutesLeft == 0 }
    }

    static func totals(_ rows: [LogRow]) -> Totals {
        Totals(minutes: rows.map(\.minutes).reduce(0, +), nightMinutes: rows.map(\.nightMinutes).reduce(0, +))
    }

    /// Whether start...end shares any time with a drive already in the log (other than `excluding`, the one
    /// being edited). Drives that only touch end to start do not overlap.
    static func overlaps(_ start: Date, _ end: Date, with rows: [LogRow], excluding: UUID?) -> Bool {
        rows.contains { r in (excluding == nil || r.id != excluding) && r.start < end && start < r.end }
    }

    /// "1:05" for 65 minutes, the way the paper log writes hours and minutes.
    static func hm(_ minutes: Int) -> String { "\(minutes / 60):" + String(format: "%02d", minutes % 60) }

    static func csv(_ rows: [LogRow], timeZone: TimeZone = .current) -> String {
        let date = DateFormatter(), time = DateFormatter()
        date.timeZone = timeZone; time.timeZone = timeZone
        date.locale = Locale(identifier: "en_US_POSIX"); time.locale = date.locale
        date.dateFormat = "MM/dd/yyyy"; time.dateFormat = "HH:mm"
        func field(_ s: String) -> String {
            // A typed route name starting with = + - @ would run as a formula in Excel; a leading ' keeps it text.
            let safe = s.first.map { "=+-@".contains($0) } == true ? "'" + s : s
            return safe.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
                ? "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : safe
        }
        var lines = ["Date,Start,End,Drive time,Day,Night,Route,Miles,Entered by hand"]
        for r in rows.sorted(by: { $0.start < $1.start }) {
            lines.append([date.string(from: r.start), time.string(from: r.start), time.string(from: r.end),
                          hm(r.minutes), hm(r.dayMinutes), hm(r.nightMinutes), field(r.routeTitle),
                          String(format: "%.1f", r.distanceMeters / 1609.34), r.manual ? "yes" : "no"].joined(separator: ","))
        }
        let t = totals(rows)
        lines.append("Total,,,\(hm(t.minutes)),\(hm(t.dayMinutes)),\(hm(t.nightMinutes)),,,")
        return lines.joined(separator: "\n") + "\n"
    }
}
