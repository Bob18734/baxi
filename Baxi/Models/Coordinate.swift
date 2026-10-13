import Foundation
import CoreLocation

/// A plain lat/lon pair that is Codable, Hashable and free of MapKit, so the core logic stays testable.
struct Coordinate: Codable, Hashable {
    var lat: Double
    var lon: Double

    var clLocation: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
    init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lon = c.longitude }
}
