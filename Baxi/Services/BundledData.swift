import Foundation

/// Loads the JSON files that ship inside the app. Built by the scripts in scripts/.
enum BundledData {
    enum LoadError: Error { case missing(String) }

    static func load<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        guard let url = Bundle.baxi.url(forResource: name, withExtension: "json") else {
            throw LoadError.missing(name)
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    static func carmelCache() throws -> OSMCache { try load("carmel_osm") }
    static func highInjuryNetwork() throws -> HighInjuryNetwork { try load("hin_2026") }
    static func intersectionStudies() throws -> IntersectionStudies { try load("intersection_studies") }
    static func farsCrashes() throws -> FARSCrashes { try load("fars_2023_hamilton") }

    /// The students' briefing notes, keyed by feature kind. Entries still blank are left out.
    static func briefings() -> [FeatureKind: Briefing] {
        guard let file: BriefingFile = try? load("briefings") else { return [:] }
        var out: [FeatureKind: Briefing] = [:]
        for e in file.entries {
            guard let kind = FeatureKind(rawValue: e.kind), !e.title.isEmpty, !e.howTo.isEmpty else { continue }
            out[kind] = e
        }
        return out
    }
}

/// One entry in Resources/Content/briefings.json. Written by hand by the students, each one citing
/// the Indiana Driver's Manual by chapter and page.
struct Briefing: Codable, Equatable {
    let kind: String
    let title: String
    let howTo: String
    let manualChapter: Int?
    let manualPage: Int?
    let quote: String

    var citation: String? {
        guard let manualChapter, let manualPage else { return nil }
        return "Indiana Driver's Manual, chapter \(manualChapter), page \(manualPage)"
    }
}

struct BriefingFile: Codable {
    let entries: [Briefing]
}

struct HighInjuryNetwork: Codable {
    struct Segment: Codable, Identifiable {
        let id: Int
        let route: String?
        let jurisdiction: String?
        let community: String?
        let county: String?
        let fatalCrashes: Double?
        let seriousInjuryCrashes: Double?
        let ksiPerMile: Double?
        let lines: [[[Double]]]
        var polylines: [[Coordinate]] { lines.map { $0.map { Coordinate(lat: $0[0], lon: $0[1]) } } }
    }
    let source: String
    let segments: [Segment]
}

struct IntersectionStudies: Codable {
    struct Intersection: Codable, Identifiable {
        let id: Int
        let name: String?
        let jurisdiction: String?
        let lat: Double?
        let lon: Double?
        let aadt: Double?
        let fatal: Double?
        let incapacitating: Double?
        let nonIncapacitating: Double?
        let propertyDamageOnly: Double?
        let total: Double?
        let studyURL: String?
    }
    let source: String
    let intersections: [Intersection]
}

struct FARSCrashes: Codable {
    struct Crash: Codable, Identifiable {
        var id: String { `case` }
        let `case`: String
        let city: String
        let lat: Double
        let lon: Double
        let road: String
        let crossRoad: String
        let intersectionType: String
        let light: String
        let month: Int
        let hour: Int
        let fatals: Int
    }
    let source: String
    let crashes: [Crash]
}

extension Bundle {
    /// The app bundle, or the resource bundle when the logic is built by Package.swift for Mac tests.
    static var baxi: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}
