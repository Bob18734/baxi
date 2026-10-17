import Foundation

/// Factual source context shown before a drive, separate from spoken navigation advice.
struct PreviewContext: Equatable {
    let source: String
    let detail: String
    let url: URL?

    static let mpoURL = URL(string: "https://indympo.gov/plans-initiatives/sap/")!
    static let farsURL = URL(string: "https://www.nhtsa.gov/research-data/fatality-analysis-reporting-system-fars")!

    /// Bundled study links may be absent or malformed. Only web links belong in Preview.
    static func webURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func study(_ study: IntersectionStudies.Intersection) -> PreviewContext {
        func count(_ value: Double?, _ label: String) -> String {
            guard let value, value.isFinite, value >= 0 else { return "\(label): not reported" }
            return "\(label): \(value.formatted(.number.precision(.fractionLength(0))))"
        }
        return PreviewContext(source: "Indianapolis MPO Intersection Safety Studies",
                              detail: [count(study.total, "Total crashes"), count(study.fatal, "Fatal crashes"),
                                       count(study.incapacitating, "Serious-injury crashes")].joined(separator: ". ")
                                + ". Counts cover the study period, not current road conditions.",
                              url: webURL(study.studyURL))
    }

    static func fatal(_ crash: FARSCrashes.Crash) -> PreviewContext {
        let road = crash.road.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = road.isEmpty ? "near this route" : "on \(road)"
        let lighting = HardSpots.lightPhrase(crash.light).map { ", \($0)" } ?? ""
        return PreviewContext(source: "NHTSA FARS 2023, Hamilton County IN",
                              detail: "A fatal crash was recorded \(place)\(lighting). Historical record \(crash.case); shown only in Preview.",
                              url: farsURL)
    }
}
