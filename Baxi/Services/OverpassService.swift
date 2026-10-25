import Foundation

/// Road data for routes outside the bundled Carmel area: everything OpenStreetMap knows within 40 m of
/// the route (roads with their lanes and limits, roundabouts and their legs, lights, stop signs) and
/// schools within 200 m, fetched from the public Overpass API when the route is planned. No key; the
/// same source and tags as scripts/build_carmel_cache.py. The drive itself then needs no connection.
enum OverpassService {
    static let mirrors = ["https://overpass-api.de/api/interpreter", "https://lz4.overpass-api.de/api/interpreter",
                          "https://z.overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter"]
    static let userAgent = "baxi-cac-2026/0.1 (student project; contact via GitHub)"
    static let routeRadiusMeters = 40
    static let schoolRadiusMeters = 200
    /// Points per query: GET URLs must stay under about 8 KB (the servers refuse longer ones; checked Oct 25,
    /// 2026: 120 points with the line written twice is 6 KB and answers), so long routes are split into pieces.
    static let pointsPerQuery = 100
    /// How long one request may take: the public servers answered a corridor in 31 to 36 s on Oct 25, 2026.
    static let requestSeconds = 40.0
    static let keepTags: Set<String> = ["highway", "junction", "lanes", "turn:lanes", "turn:lanes:forward", "turn:lanes:backward",
                                        "lanes:forward", "lanes:backward", "oneway", "maxspeed", "name", "ref", "amenity", "stop", "railway"]

    enum FetchError: Error { case allMirrorsFailed }

    /// The road data along `line`, merged across the query pieces.
    static func corridor(along line: Polyline) async throws -> OSMCache {
        var ways: [Int: OSMWay] = [:], nodes: [Int: OSMNode] = [:]
        // The pieces are fetched at the same time (a route has one to a few), so a long route waits
        // about as long as a short one.
        let parts = try await withThrowingTaskGroup(of: OSMCache.self) { group in
            for piece in pieces(of: line) { group.addTask { try await fetch(query(around: piece)) } }
            return try await group.reduce(into: [OSMCache]()) { $0.append($1) }
        }
        for part in parts {
            for w in part.ways { ways[w.id] = merge(ways[w.id], w) }
            for n in part.nodes { nodes[n.id] = n }
        }
        let box = GeoBox(line.points)
        return OSMCache(source: "OpenStreetMap contributors, ODbL, via Overpass API", bbox: "\(box.minLat),\(box.minLon),\(box.maxLat),\(box.maxLon)",
                        fetched: ISO8601DateFormatter().string(from: Date()).prefix(10).description,
                        ways: Array(ways.values), nodes: Array(nodes.values))
    }

    /// The route's ends are not sent: the first and last 200 m stay on the phone, so neither the start
    /// (often home) nor the destination address goes to the Overpass server.
    static let privateEndMeters = 200.0

    /// The route as points every ~80 m (enough for a 40 m corridor), its private ends left out, in pieces
    /// that overlap by one point.
    static func pieces(of line: Polyline) -> [[Coordinate]] {
        let keep = (privateEndMeters, line.lengthMeters - privateEndMeters)
        let pts = line.samples(everyMeters: 80).filter { $0.alongMeters >= keep.0 && $0.alongMeters <= keep.1 }.map(\.point)
        guard pts.count > 1 else { return pts.isEmpty ? [] : [pts] }
        var out: [[Coordinate]] = [], i = 0
        while i < pts.count - 1 {
            let end = min(pts.count, i + pointsPerQuery)
            out.append(Array(pts[i..<end]))
            i = end - 1
        }
        return out
    }

    static func query(around pts: [Coordinate]) -> String {
        let line = pts.map { String(format: "%.5f,%.5f", $0.lat, $0.lon) }.joined(separator: ",")
        // Signals, stop signs and crossings are nodes of the roads already found, so they come from those ways
        // instead of a second search along the line: the line appears twice, and the query runs in a third of the time.
        return """
        [out:json][timeout:\(Int(requestSeconds))];
        way(around:\(routeRadiusMeters),\(line))["highway"]->.w;
        way.w["junction"="roundabout"]->.rb;
        node(w.rb)->.rbn;
        way(bn.rbn)["highway"]->.legs;
        (.w; .legs;);
        out body geom;
        node(w.w)["highway"~"^(traffic_signals|stop)$"];
        out;
        node(w.w)["railway"="level_crossing"];
        out;
        nwr(around:\(schoolRadiusMeters),\(line))["amenity"="school"];
        out center tags;
        """
    }

    private static func fetch(_ query: String) async throws -> OSMCache {
        for url in mirrors {
            var c = URLComponents(string: url)!
            c.queryItems = [URLQueryItem(name: "data", value: query)]
            // GET, not POST: overpass-api.de answered POST with an HTML error page on Oct 13, 2026.
            var req = URLRequest(url: c.url!, timeoutInterval: requestSeconds)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  data.count < 20_000_000,   // a corridor is a few hundred KB; anything near that size is not one
                  let parsed = try? parse(data) else { continue }
            return parsed
        }
        throw FetchError.allMirrorsFailed
    }

    /// Overpass JSON into the same shape as the bundled cache.
    static func parse(_ data: Data) throws -> OSMCache {
        struct Element: Decodable {
            struct LatLon: Decodable { let lat: Double; let lon: Double }
            let type: String
            let id: Int
            let tags: [String: String]?
            let nodes: [Int]?
            let geometry: [LatLon?]?
            let lat: Double?
            let lon: Double?
            let center: LatLon?
        }
        struct Body: Decodable { let elements: [Element] }
        let body = try JSONDecoder().decode(Body.self, from: data)
        var ways: [Int: OSMWay] = [:], nodes: [OSMNode] = []
        for e in body.elements {
            let tags = (e.tags ?? [:]).filter { keepTags.contains($0.key) }
            if e.type == "node", let lat = e.lat, let lon = e.lon {
                nodes.append(OSMNode(id: e.id, tags: tags, lat: lat, lon: lon))
            } else if e.type == "way" {
                // Geometry entries can be null where a node lies outside the query area; keep nodes and
                // geometry aligned by dropping both.
                var ids: [Int] = [], geom: [[Double]] = []
                if let g = e.geometry, let n = e.nodes, g.count == n.count {
                    for (id, p) in zip(n, g) { if let p { ids.append(id); geom.append([p.lat, p.lon]) } }
                }
                let w = OSMWay(id: e.id, tags: tags, nodes: ids.isEmpty ? e.nodes : ids, geometry: geom.isEmpty ? nil : geom,
                               lat: e.center?.lat, lon: e.center?.lon)
                ways[e.id] = merge(ways[e.id], w)
            }
        }
        return OSMCache(source: "OpenStreetMap contributors, ODbL, via Overpass API", bbox: "", fetched: "",
                        ways: Array(ways.values), nodes: nodes)
    }

    /// The same way seen twice (in two pieces, or once as a school center): keep the one with geometry.
    static func merge(_ a: OSMWay?, _ b: OSMWay) -> OSMWay {
        guard let a else { return b }
        return (b.geometry?.count ?? 0) > (a.geometry?.count ?? 0) ? b : a
    }

    /// The bundled cache plus fetched data, without duplicates.
    static func combine(_ base: OSMCache, _ extra: OSMCache) -> OSMCache {
        var ways = Dictionary(base.ways.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for w in extra.ways { ways[w.id] = merge(ways[w.id], w) }
        var nodes = Dictionary(base.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for n in extra.nodes { nodes[n.id] = n }
        return OSMCache(source: base.source, bbox: base.bbox, fetched: base.fetched, ways: Array(ways.values), nodes: Array(nodes.values))
    }
}
