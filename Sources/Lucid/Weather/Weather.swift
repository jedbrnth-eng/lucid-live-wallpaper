// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Weather wallpapers, as pure logic: the Open-Meteo request (HTTPS, coordinates rounded to ~10 km, nothing else
// sent), a strict size-limited parser for its response, WMO weather codes, rate limiting with back-off, cache
// freshness and the per-condition rule. Weather data: Open-Meteo.com, CC BY 4.0 (https://open-meteo.com/en/licence).
import Foundation

enum WeatherCondition: String, Codable, CaseIterable {
    case clear, cloudy, rain, snow

    /// WMO weather interpretation codes as documented by Open-Meteo (https://open-meteo.com/en/docs).
    init?(wmo c: Int) {
        switch c {
        case 0, 1: self = .clear
        case 2, 3, 45, 48: self = .cloudy
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99: self = .rain
        case 71, 73, 75, 77, 85, 86: self = .snow
        default: return nil
        }
    }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .clear: return "sun.max"
        case .cloudy: return "cloud"
        case .rain: return "cloud.rain"
        case .snow: return "cloud.snow"
        }
    }
}

struct WeatherReport: Equatable {
    var code: Int
    var isDay: Bool?
    var condition: WeatherCondition
}

enum WeatherParser {
    static let maxBytes = 64 * 1024

    /// Only `current.weather_code` (an integer 0-99) is read. Anything else unexpected gives nil, never a crash.
    static func parse(_ d: Data) -> WeatherReport? {
        guard !d.isEmpty, d.count <= maxBytes,
              let root = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let cur = root["current"] as? [String: Any],
              let n = cur["weather_code"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let v = n.doubleValue
        guard v.isFinite, v == v.rounded(), v >= 0, v <= 99 else { return nil }
        let code = Int(v)
        guard let cond = WeatherCondition(wmo: code) else { return nil }
        let isDay = (cur["is_day"] as? NSNumber).map { $0.intValue == 1 }
        return WeatherReport(code: code, isDay: isDay, condition: cond)
    }
}

enum WeatherRequest {
    static let host = "api.open-meteo.com"
    /// Approximate location only: rounded to one decimal (about 10 km). No key, no account, no other parameters.
    static func url(latitude: Double, longitude: Double) -> URL {
        let lat = (min(90, max(-90, latitude)) * 10).rounded() / 10
        let lon = (min(180, max(-180, longitude)) * 10).rounded() / 10
        var c = URLComponents()
        c.scheme = "https"; c.host = host; c.path = "/v1/forecast"
        c.queryItems = [URLQueryItem(name: "latitude", value: String(format: "%.1f", lat)),
                        URLQueryItem(name: "longitude", value: String(format: "%.1f", lon)),
                        URLQueryItem(name: "current", value: "weather_code,is_day")]
        return c.url ?? URL(fileURLWithPath: "/")
    }
}

struct WeatherFetchState: Codable, Equatable {
    var lastAttempt: Date?
    var lastSuccess: Date?
    var failures = 0
    var recent: [Date] = []   // attempts in the last 24 h

    mutating func recordSuccess(at t: Date) { lastAttempt = t; lastSuccess = t; failures = 0; note(t) }
    mutating func recordFailure(at t: Date) { lastAttempt = t; failures += 1; note(t) }
    private mutating func note(_ t: Date) { recent = recent.filter { abs(t.timeIntervalSince($0)) < 86_400 } + [t] }
}

enum WeatherPolicy {
    static let minInterval: TimeInterval = 30 * 60
    static let maxPerDay = 60   // far below Open-Meteo's free limit of 10,000 calls a day
    static func retryDelay(failures: Int) -> TimeInterval { min(6 * 3600, 5 * 60 * pow(2, Double(max(0, failures - 1)))) }

    static func shouldFetch(_ s: WeatherFetchState, now: Date) -> Bool {
        if s.recent.filter({ now.timeIntervalSince($0) < 86_400 && now >= $0 }).count >= maxPerDay { return false }
        guard let last = s.lastAttempt else { return true }
        if now < last.addingTimeInterval(-3600) { return true }   // the clock moved back a lot: start over
        let wait = s.failures > 0 ? retryDelay(failures: s.failures) : minInterval
        return now >= last.addingTimeInterval(wait)
    }
}

/// Last good reading, saved as weather.json. Older than 3 hours = unknown (rules stop overriding).
struct WeatherCache: Codable, Equatable {
    var condition: WeatherCondition
    var fetchedAt: Date
    static let maxAge: TimeInterval = 3 * 3600
    func current(now: Date) -> WeatherCondition? {
        let age = now.timeIntervalSince(fetchedAt)
        return age >= 0 && age <= Self.maxAge ? condition : nil
    }
}

/// "When it rains, show this": a wallpaper per condition. Conditions without one leave the normal wallpaper.
struct WeatherRule: Codable, Equatable {
    var map: [WeatherCondition: Assignment]
    init(map: [WeatherCondition: Assignment]) { self.map = map }
    func pick(_ c: WeatherCondition?) -> Assignment? { c.flatMap { map[$0] } }

    private enum CodingKeys: String, CodingKey { case map }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = ((try? c.decodeIfPresent(LossyDictionary<Assignment>.self, forKey: .map)) ?? nil)?.values ?? [:]
        map = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in WeatherCondition(rawValue: k).map { ($0, v) } })
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) }), forKey: .map)
    }
}
