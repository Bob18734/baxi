import Testing
@testable import FirstRoads

struct GeoTests {
    @Test func distanceAcrossCarmel() {
        let cityCenter = Coordinate(lat: 39.9765, lon: -86.1281)
        let hazelDell126 = Coordinate(lat: 39.9594, lon: -86.0605)
        let d = Geo.distanceMeters(cityCenter, hazelDell126)
        #expect(d > 5_800 && d < 6_300)
    }

    @Test func bearingNorthAndEast() {
        let a = Coordinate(lat: 39.9, lon: -86.1)
        #expect(abs(Geo.bearingDegrees(from: a, to: Coordinate(lat: 39.91, lon: -86.1)) - 0) < 0.5)
        #expect(abs(Geo.bearingDegrees(from: a, to: Coordinate(lat: 39.9, lon: -86.09)) - 90) < 0.5)
    }

    @Test func pointToPolyline() {
        let line = [Coordinate(lat: 39.90, lon: -86.10), Coordinate(lat: 39.90, lon: -86.09)]
        let onLine = Coordinate(lat: 39.90, lon: -86.095)
        let offLine = Coordinate(lat: 39.901, lon: -86.095)   // about 111 m north
        #expect(Geo.distanceMeters(from: onLine, toPolyline: line) < 1)
        let d = Geo.distanceMeters(from: offLine, toPolyline: line)
        #expect(d > 100 && d < 125)
    }
}
