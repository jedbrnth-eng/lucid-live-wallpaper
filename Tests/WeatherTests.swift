// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Weather wallpapers: parsing recorded Open-Meteo responses, WMO codes, the privacy of the request, rate limiting,
// cache freshness, and weather rules in saved state. Offline: no test touches the network or the real clock.
import Foundation

private func weatherFixture(_ name: String) throws -> Data {
    let root = ProcessInfo.processInfo.environment["LUCID_FIXTURES"] ?? "Tests/Fixtures"
    return try Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("weather").appendingPathComponent(name))
}

func registerWeatherTests() {
    test("Weather: a recorded Open-Meteo response parses (Bangkok, drizzle -> rain)") {
        guard let r = WeatherParser.parse(try weatherFixture("open-meteo-bangkok-drizzle.json")) else { expect(false, "no report"); return }
        expectEqual(r.code, 51)
        expectEqual(r.condition, .rain)
        expectEqual(r.isDay, true)
    }
    test("Weather: recorded fog (Svalbard) counts as cloudy; the API's error shape gives no report") {
        expectEqual(WeatherParser.parse(try weatherFixture("open-meteo-svalbard.json"))?.condition, .cloudy)
        expectEqual(WeatherParser.parse(try weatherFixture("open-meteo-error.json")), nil)
    }
    test("Weather: WMO codes map to clear, cloudy, rain and snow") {
        for c in [0, 1] { expectEqual(WeatherCondition(wmo: c), .clear, "\(c)") }
        for c in [2, 3, 45, 48] { expectEqual(WeatherCondition(wmo: c), .cloudy, "\(c)") }
        for c in [51, 55, 56, 61, 65, 67, 80, 82, 95, 96, 99] { expectEqual(WeatherCondition(wmo: c), .rain, "\(c)") }
        for c in [71, 73, 75, 77, 85, 86] { expectEqual(WeatherCondition(wmo: c), .snow, "\(c)") }
        expectEqual(WeatherCondition(wmo: 42), nil, "unassigned code")
        expectEqual(WeatherCondition(wmo: -1), nil)
    }
    test("Weather: malformed, oversized or hostile responses never crash and give no report") {
        let cases: [String] = [
            "", "null", "[]", "not json", #"{"current":{}}"#, #"{"current":{"weather_code":"51"}}"#,
            #"{"current":{"weather_code":150}}"#, #"{"current":{"weather_code":1e308}}"#, #"{"current":[1,2,3]}"#,
            #"{"current":{"weather_code":51.7}}"#,
        ]
        for c in cases { expectEqual(WeatherParser.parse(Data(c.utf8)), nil, c) }
        let huge = Data(#"{"current":{"weather_code":0},"x":""#.utf8) + Data(repeating: 0x61, count: 70_000) + Data(#""}"#.utf8)
        expectEqual(WeatherParser.parse(huge), nil, "over the 64 KB limit")
        expectEqual(WeatherParser.parse(Data(#"{"current":{"weather_code":3}}"#.utf8))?.condition, .cloudy, "is_day is optional")
    }
    test("Weather: the request is HTTPS to Open-Meteo with coordinates rounded to about 10 km and nothing else") {
        let u = WeatherRequest.url(latitude: 13.756_331, longitude: 100.501_765)
        expectEqual(u.scheme, "https")
        expectEqual(u.host, "api.open-meteo.com")
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        expectEqual(q["latitude"], "13.8")
        expectEqual(q["longitude"], "100.5")
        expectEqual(Set(q.keys), ["latitude", "longitude", "current"])
        expectEqual(WeatherRequest.url(latitude: -0.04, longitude: 200).absoluteString.contains("latitude=0.0") ||
                    WeatherRequest.url(latitude: -0.04, longitude: 200).absoluteString.contains("latitude=-0.0"), true)
        expect(WeatherRequest.url(latitude: 95, longitude: 200).absoluteString.contains("latitude=90.0&longitude=180.0"), "clamped")
    }
    test("Weather: fetch at most every 30 min, back off after failures, cap calls per day") {
        let t0 = Date(timeIntervalSince1970: 2_000_000_000)
        var s = WeatherFetchState()
        expect(WeatherPolicy.shouldFetch(s, now: t0), "first fetch")
        s.recordSuccess(at: t0)
        expect(!WeatherPolicy.shouldFetch(s, now: t0.addingTimeInterval(29 * 60)))
        expect(WeatherPolicy.shouldFetch(s, now: t0.addingTimeInterval(30 * 60)))
        s.recordFailure(at: t0.addingTimeInterval(30 * 60))
        expect(!WeatherPolicy.shouldFetch(s, now: t0.addingTimeInterval(34 * 60)), "5 min after one failure")
        expect(WeatherPolicy.shouldFetch(s, now: t0.addingTimeInterval(35 * 60)))
        for i in 0..<20 { s.recordFailure(at: t0.addingTimeInterval(Double(36 + i) * 60)) }
        expectEqual(WeatherPolicy.retryDelay(failures: s.failures), 6 * 3600, "backoff caps at 6 h")
        var busy = WeatherFetchState()
        for i in 0..<WeatherPolicy.maxPerDay { busy.recordSuccess(at: t0.addingTimeInterval(Double(i))) }
        expect(!WeatherPolicy.shouldFetch(busy, now: t0.addingTimeInterval(3 * 3600)), "daily cap reached")
        expect(WeatherPolicy.shouldFetch(busy, now: t0.addingTimeInterval(25 * 3600)), "a new day")
        expect(!WeatherPolicy.shouldFetch(s, now: t0.addingTimeInterval(-3600)) || true, "clock moved back does not crash")
    }
    test("Weather: a cached reading counts for 3 hours, then the rule goes quiet") {
        let t0 = Date(timeIntervalSince1970: 2_000_000_000)
        let c = WeatherCache(condition: .snow, fetchedAt: t0)
        expectEqual(c.current(now: t0.addingTimeInterval(2 * 3600)), .snow)
        expectEqual(c.current(now: t0.addingTimeInterval(3 * 3600 + 1)), nil)
        expectEqual(c.current(now: t0.addingTimeInterval(-7200)), nil, "reading from the future (clock change) is ignored")
    }
    let rain = Assignment(itemID: "r", title: "Rain", path: "/r.mp4", kind: .video)
    let snow = Assignment(itemID: "s", title: "Snow", path: "/s.mp4", kind: .video)
    test("Weather: a rule overrides only for conditions it has a wallpaper for") {
        let rule = WeatherRule(map: [.rain: rain, .snow: snow])
        expectEqual(rule.pick(.rain), rain)
        expectEqual(rule.pick(.clear), nil)
        expectEqual(rule.pick(nil), nil, "no fresh reading: no override")
    }
    test("Weather: rules save/load; old state.json has none; a broken entry drops alone") {
        var s = EngineState(); s.weather = [EngineState.allKey: WeatherRule(map: [.rain: rain])]
        let back = try JSONDecoder().decode(EngineState.self, from: JSONEncoder().encode(s))
        expectEqual(back.weather?[EngineState.allKey]?.pick(.rain), rain)
        let old = #"{"perScreen":{},"userPaused":false}"#
        expect(SavedData.state(Data(old.utf8))?.weather == nil)
        let mixed = #"{"perScreen":{},"weather":{"*":{"map":{"rain":{"itemID":"r","title":"Rain","path":"/r.mp4","kind":"video"},"hail":{"x":1}}}}}"#
        expectEqual(SavedData.state(Data(mixed.utf8))?.weather?[EngineState.allKey]?.pick(.rain), rain, "unknown condition key skipped")
    }
}
