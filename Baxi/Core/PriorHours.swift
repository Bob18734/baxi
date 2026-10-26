import Foundation

/// Supervised hours driven before Baxi (entered at setup or later in the Log). They count toward the 50 and the 10
/// at night on every screen, but they are not rows on the official State Form 54706, which lists each drive with
/// its date: those hours stay on the driver's paper log.
struct PriorHours: Codable, Equatable {
    var dayMinutes = 0
    var nightMinutes = 0

    var totalMinutes: Int { dayMinutes + nightMinutes }
    var isEmpty: Bool { totalMinutes == 0 }

    /// No negatives, and no more than twice the requirement (a typo, not a driving history).
    var clamped: PriorHours {
        let cap = DriveLog.requiredMinutes * 2
        return PriorHours(dayMinutes: min(cap, max(0, dayMinutes)), nightMinutes: min(cap, max(0, nightMinutes)))
    }

    static let key = "priorHours"

    static func load(_ defaults: UserDefaults = .standard) -> PriorHours {
        guard let data = defaults.data(forKey: key), let p = try? JSONDecoder().decode(PriorHours.self, from: data) else { return PriorHours() }
        return p.clamped
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(clamped), forKey: Self.key)
    }
}

extension DriveLog {
    /// Totals toward the requirement, counting the hours driven before Baxi.
    static func totals(_ rows: [LogRow], prior: PriorHours) -> Totals {
        let logged = totals(rows)
        return Totals(minutes: logged.minutes + prior.totalMinutes, nightMinutes: logged.nightMinutes + prior.nightMinutes)
    }
}
