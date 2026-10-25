import Foundation
import CoreLocation

/// Only the most recent route request may update the map or its loading state.
struct RouteRequestState {
    private var current: UUID?
    var isRouting: Bool { current != nil }
    mutating func begin() -> UUID {
        let id = UUID()
        current = id
        return id
    }
    func accepts(_ id: UUID) -> Bool { current == id }
    mutating func finish(_ id: UUID) {
        if accepts(id) { current = nil }
    }
    mutating func cancel() { current = nil }
}

/// A one-time planning fix must be recent and accurate enough to identify a starting road.
enum PlanningLocationPolicy {
    static func accepts(_ location: CLLocation, now: Date = Date()) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 100
            && now.timeIntervalSince(location.timestamp) >= -5
            && now.timeIntervalSince(location.timestamp) <= 30
    }
}
