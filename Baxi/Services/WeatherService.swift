import Foundation

/// Weather where a drive starts, from the National Weather Service (api.weather.gov: free, no key,
/// public domain). Active alerts and the current hour's forecast become one plain line on the Routes
/// screen and, when roads may be affected, one spoken line as the drive starts. The location sent is
/// rounded to two decimals (about 1 km).
struct RoadWeather: Equatable {
    enum Condition: Int, Comparable, CaseIterable {
        case clear, wind, rain, fog, storm, snowOrIce
        static func < (a: Condition, b: Condition) -> Bool { a.rawValue < b.rawValue }
    }

    /// "Light Rain, 48°F"
    let summary: String
    let condition: Condition
    /// NWS alert names in effect, most severe first: "Winter Weather Advisory".
    let alerts: [String]

    /// Said once as the drive starts, or nil when the weather does not change the drive.
    var spoken: String? {
        let alert = alerts.first.map { "\($0) in effect. " } ?? ""
        switch condition {
        case .clear: return alerts.isEmpty ? nil : alert.trimmingCharacters(in: .whitespaces)
        case .wind: return alert + "Strong wind right now."
        case .rain: return alert + "Rain right now. Roads may be slippery."
        case .fog: return alert + "Fog right now. You may not see far ahead."
        case .storm: return alert + "Thunderstorms nearby. Roads may be slippery."
        case .snowOrIce: return alert + "Snow or ice possible. Roads may be slippery."
        }
    }

    /// Reads NWS short-forecast wording ("Chance Light Rain", "Patchy Fog", "Freezing Drizzle").
    static func condition(forecast: String, alerts: [String]) -> Condition {
        let text = ([forecast] + alerts).joined(separator: " ").lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        if has("snow", "ice", "freezing", "sleet", "blizzard", "winter") { return .snowOrIce }
        if has("thunderstorm", "t-storm", "tornado") { return .storm }
        if has("fog") { return .fog }
        if has("rain", "showers", "drizzle", "flood") { return .rain }
        if has("wind") { return .wind }
        return .clear
    }
}

enum WeatherService {
    static let userAgent = "(baxi-cac-2026, student project; contact via GitHub)"

    static func weather(at c: Coordinate) async throws -> RoadWeather {
        let point = String(format: "%.2f,%.2f", c.lat, c.lon)
        async let alertsData = get("https://api.weather.gov/alerts/active?point=\(point)")
        let pointsData = try await get("https://api.weather.gov/points/\(point)")
        guard let hourlyURL = try hourlyForecastURL(pointsData) else { throw URLError(.badServerResponse) }
        let hourlyData = try await get(hourlyURL)
        let alerts = (try? await alertNames(alertsData)) ?? []
        guard let now = try firstPeriod(hourlyData) else { throw URLError(.badServerResponse) }
        return RoadWeather(summary: "\(now.shortForecast), \(now.temperature)°\(now.temperatureUnit)",
                           condition: RoadWeather.condition(forecast: now.shortForecast, alerts: alerts), alerts: alerts)
    }

    private static func get(_ url: String) async throws -> Data {
        // The hourly link comes from the server's own answer: it must still be the weather service, over https.
        guard let u = URL(string: url), u.scheme == "https", u.host() == "api.weather.gov" else { throw URLError(.badURL) }
        var req = URLRequest(url: u, timeoutInterval: 15)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    // Parsing, separate so it can be tested offline.

    static func hourlyForecastURL(_ data: Data) throws -> String? {
        struct Points: Decodable { struct P: Decodable { let forecastHourly: String? }; let properties: P }
        return try JSONDecoder().decode(Points.self, from: data).properties.forecastHourly
    }

    struct Period: Decodable { let shortForecast: String; let temperature: Int; let temperatureUnit: String }

    static func firstPeriod(_ data: Data) throws -> Period? {
        struct Forecast: Decodable { struct P: Decodable { let periods: [Period] }; let properties: P }
        return try JSONDecoder().decode(Forecast.self, from: data).properties.periods.first
    }

    /// Alert names, most severe first, without duplicates.
    static func alertNames(_ data: Data) throws -> [String] {
        struct Alerts: Decodable {
            struct F: Decodable { struct P: Decodable { let event: String; let severity: String? }; let properties: P }
            let features: [F]
        }
        let rank = ["Extreme": 0, "Severe": 1, "Moderate": 2, "Minor": 3]
        let props = try JSONDecoder().decode(Alerts.self, from: data).features.map(\.properties)
            .sorted { rank[$0.severity ?? "", default: 4] < rank[$1.severity ?? "", default: 4] }
        var seen = Set<String>()
        return props.map(\.event).filter { seen.insert($0).inserted }
    }
}
