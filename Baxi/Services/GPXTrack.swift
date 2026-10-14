import Foundation

/// A recorded or synthetic drive: ordered points with optional timestamps. The Simulator and the
/// Drive screen's replay mode feed these to RouteFollower exactly like real location fixes.
struct GPXPoint: Equatable {
    let coordinate: Coordinate
    let time: Date?
}

enum GPXTrack {
    /// Parses <trkpt lat lon><time>…</time></trkpt> elements (also <rtept> and <wpt>).
    static func parse(_ data: Data) -> [GPXPoint] {
        let delegate = Parser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.points
    }

    /// Writes a track at a constant speed, one point per `stepSeconds`, along a polyline.
    static func synthesize(along line: Polyline, speedMps: Double, stepSeconds: Double = 1, start: Date = Date()) -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Baxi"><trk><name>Baxi replay</name><trkseg>

        """
        let fmt = ISO8601DateFormatter()
        var m = 0.0, t = 0.0
        func emit(_ c: Coordinate) {
            out += "<trkpt lat=\"\(c.lat)\" lon=\"\(c.lon)\"><time>\(fmt.string(from: start.addingTimeInterval(t)))</time></trkpt>\n"
        }
        while m < line.lengthMeters {
            if let c = line.coordinate(atMeters: m) { emit(c) }
            m += speedMps * stepSeconds
            t += stepSeconds
        }
        if let last = line.points.last { emit(last) }   // always end exactly at the destination
        return out + "</trkseg></trk></gpx>\n"
    }

    private final class Parser: NSObject, XMLParserDelegate {
        var points: [GPXPoint] = []
        private var current: (lat: Double, lon: Double)?
        private var text = ""
        private var time: Date?
        private let iso = ISO8601DateFormatter()
        private let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if ["trkpt", "rtept", "wpt"].contains(name), let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) {
                current = (lat, lon); time = nil
            }
            text = ""
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "time", current != nil {
                let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
                time = iso.date(from: s) ?? isoFrac.date(from: s)
            }
            if ["trkpt", "rtept", "wpt"].contains(name), let c = current {
                points.append(GPXPoint(coordinate: Coordinate(lat: c.lat, lon: c.lon), time: time))
                current = nil
            }
        }
    }
}
