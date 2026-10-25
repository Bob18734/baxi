import Foundation
import CoreLocation

/// One recent location fix, for where a searched route starts. nil when location is off, not yet
/// allowed, or no good fix arrives in time.
@MainActor
enum CurrentLocation {
    static func once(timeout: TimeInterval = 4) async -> Coordinate? {
        let probe = Probe()
        return await Deadline.run(seconds: timeout) { await probe.fix() } ?? nil
    }

    /// Lives until its fix arrives; CLLocationManager must be made and used on the main thread.
    private final class Probe: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
        private var manager: CLLocationManager?
        private var continuation: CheckedContinuation<Coordinate?, Never>?

        func fix() async -> Coordinate? {
            await withCheckedContinuation { c in
                DispatchQueue.main.async {
                    self.continuation = c
                    let m = CLLocationManager()
                    m.delegate = self
                    m.desiredAccuracy = kCLLocationAccuracyHundredMeters
                    self.manager = m
                    switch m.authorizationStatus {
                    case .denied, .restricted: self.finish(nil)
                    case .notDetermined: m.requestWhenInUseAuthorization()
                    default: m.requestLocation()
                    }
                }
            }
        }

        private func finish(_ c: Coordinate?) {
            continuation?.resume(returning: c); continuation = nil
            manager?.delegate = nil; manager = nil
        }

        func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
            switch m.authorizationStatus {
            case .denied, .restricted: finish(nil)
            case .notDetermined: break
            default: m.requestLocation()
            }
        }

        func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            // A cached fix from long ago would start the route somewhere the car no longer is.
            guard let l = locations.last(where: { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 100
                && abs($0.timestamp.timeIntervalSinceNow) < 60 }) else { return }
            finish(Coordinate(l.coordinate))
        }

        func locationManager(_ m: CLLocationManager, didFailWithError error: Error) { finish(nil) }
    }
}
