import Foundation

/// Turns raw OpenStreetMap elements into typed RoadFeatures with tiers.
/// Roundabouts are grouped from their ways and handed to RoundaboutClassifier (Vardaan's module).
enum FeatureExtractor {
    static func extract(from cache: OSMCache) -> [RoadFeature] {
        var out: [RoadFeature] = []
        out += nodeFeatures(cache.nodes)
        out += roundaboutFeatures(cache.ways)
        out += roadFeatures(cache.ways)
        out += schoolFeatures(cache.ways)
        return out
    }

    // MARK: Nodes: stop signs, signals, schools mapped as points

    private static func nodeFeatures(_ nodes: [OSMNode]) -> [RoadFeature] {
        nodes.compactMap { n in
            let kind: FeatureKind?
            switch (n.tags["highway"], n.tags["amenity"]) {
            case ("traffic_signals", _): kind = .trafficSignal
            case ("stop", _): kind = .stopSign
            case (_, "school"): kind = .schoolZone
            default: kind = nil
            }
            guard let kind else { return nil }
            return RoadFeature(id: "n\(n.id)", kind: kind, coordinate: n.coordinate, name: n.tags["name"],
                               lanes: nil, legs: nil, maxspeedMph: nil, osmIds: [n.id])
        }
    }

    private static func schoolFeatures(_ ways: [OSMWay]) -> [RoadFeature] {
        ways.compactMap { w in
            guard w.tags["amenity"] == "school", let c = w.center else { return nil }
            return RoadFeature(id: "w\(w.id)", kind: .schoolZone, coordinate: c, name: w.name,
                               lanes: nil, legs: nil, maxspeedMph: nil, osmIds: [w.id])
        }
    }

    // MARK: Roundabouts

    /// Groups roundabout ways that share nodes into one roundabout each, finds the touching legs,
    /// and asks the classifier what kind it is.
    static func roundaboutFeatures(_ ways: [OSMWay]) -> [RoadFeature] {
        let circles = ways.filter { $0.isRoundabout && $0.nodes != nil }
        let others = ways.filter { !$0.isRoundabout && $0.nodes != nil && $0.highway != nil }
        var nodeToOther: [Int: [OSMWay]] = [:]
        for w in others { for n in w.nodes ?? [] { nodeToOther[n, default: []].append(w) } }

        var features: [RoadFeature] = []
        for group in groupBySharedNodes(circles) {
            let nodeSet = Set(group.flatMap { $0.nodes ?? [] })
            var touching: [Int: OSMWay] = [:]
            for n in nodeSet { for w in nodeToOther[n] ?? [] { touching[w.id] = w } }
            let input = RoundaboutInput(circleWays: group, touchingWays: Array(touching.values))
            let result = RoundaboutClassifier.classify(input)
            let pts = group.flatMap(\.coordinates)
            guard let center = Geo.centroid(pts) else { continue }
            let kind: FeatureKind
            switch result.classification {
            case .singleLane: kind = .singleLaneRoundabout
            case .multiLane: kind = .multiLaneRoundabout
            case .interchange: kind = .interchangeRoundabout
            }
            let name = group.compactMap(\.name).first ?? touching.values.compactMap(\.name).first
            features.append(RoadFeature(id: "rb\(group.map(\.id).min() ?? 0)", kind: kind, coordinate: center,
                                        name: name, lanes: result.lanes, legs: result.legs,
                                        maxspeedMph: group.compactMap(\.maxspeedMph).max(),
                                        osmIds: group.map(\.id)))
        }
        return features
    }

    /// Union-find over ways: two ways are in the same group when they share any node id.
    static func groupBySharedNodes(_ ways: [OSMWay]) -> [[OSMWay]] {
        var parent = Array(0..<ways.count)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        var firstOwner: [Int: Int] = [:]
        for (i, w) in ways.enumerated() {
            for n in w.nodes ?? [] {
                if let j = firstOwner[n] { parent[find(i)] = find(j) } else { firstOwner[n] = i }
            }
        }
        var groups: [Int: [OSMWay]] = [:]
        for (i, w) in ways.enumerated() { groups[find(i), default: []].append(w) }
        return Array(groups.values)
    }

    // MARK: Roads by posted speed and ramps

    /// One feature per named road per kind, placed on its longest segment, so a 3-mile parkway
    /// split into 40 OSM ways is one "45 mph road" and not 40 markers.
    private static func roadFeatures(_ ways: [OSMWay]) -> [RoadFeature] {
        var groups: [String: [(way: OSMWay, kind: FeatureKind)]] = [:]
        for w in ways {
            guard !w.isRoundabout, let hw = w.highway, w.center != nil else { continue }
            let kind: FeatureKind?
            if hw == "motorway_link" || hw == "trunk_link" {
                kind = .highwayRamp
            } else if let mph = w.maxspeedMph {
                switch mph {
                case 40...45: kind = .road40to45
                case 50...54: kind = .road50
                default: kind = nil   // 55+ is the highway itself, reached through ramps. Under 40 is neighborhood driving.
                }
            } else { kind = nil }
            guard let kind else { continue }
            // Ramps stay individual (each one is its own merge). Roads group by name.
            let key = kind == .highwayRamp ? "ramp-\(w.id)" : "\(kind.rawValue)-\(w.name ?? "way\(w.id)")"
            groups[key, default: []].append((w, kind))
        }
        return groups.map { _, members in
            let longest = members.max { lengthMeters($0.way) < lengthMeters($1.way) }!
            return RoadFeature(id: "w\(longest.way.id)", kind: longest.kind, coordinate: longest.way.center!,
                               name: longest.way.name, lanes: longest.way.lanes, legs: nil,
                               maxspeedMph: members.compactMap(\.way.maxspeedMph).max(),
                               osmIds: members.map(\.way.id))
        }
        .sorted { $0.id < $1.id }
    }

    static func lengthMeters(_ w: OSMWay) -> Double {
        let pts = w.coordinates
        guard pts.count > 1 else { return 0 }
        return zip(pts, pts.dropFirst()).map { Geo.distanceMeters($0, $1) }.reduce(0, +)
    }
}
