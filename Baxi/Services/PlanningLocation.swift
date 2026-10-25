import Foundation
import CoreLocation
import Observation

/// One-shot location for trip planning. Stops on success, failure, timeout or sheet dismissal.
@MainActor @Observable
final class PlanningLocation: NSObject, CLLocationManagerDelegate {
    private(set) var isLocating = false
    private(set) var error: String?
    private(set) var coordinate: Coordinate?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func request() {
        cancel()
        coordinate = nil
        error = nil
        isLocating = true
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.fail("Could not find a precise location. Try again outdoors or search for a starting place.")
        }
        authorizeOrLocate()
    }

    func cancel() {
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        isLocating = false
    }

    private func fail(_ message: String) {
        error = message
        cancel()
    }

    private func authorizeOrLocate() {
        guard isLocating else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        case .denied, .restricted:
            fail("Location access is off. Enable it in Settings, or search for a starting place.")
        @unknown default: fail("Location is unavailable. Search for a starting place instead.")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizeOrLocate() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self, self.isLocating,
                  let fix = locations.last(where: { PlanningLocationPolicy.accepts($0) }) else { return }
            self.coordinate = Coordinate(fix.coordinate)
            self.cancel()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let unavailable = (error as? CLError)?.code == .locationUnknown
        Task { @MainActor [weak self] in
            guard let self, self.isLocating, !unavailable else { return }
            self.fail("Could not get your location. Try again or search for a starting place.")
        }
    }
}
