// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Fetches the current weather from Open-Meteo (free, no key) only when the user has turned Weather wallpapers on
// AND set at least one weather wallpaper. Approximate location only (rounded to ~10 km; from the time zone unless
// the user already allowed location for Day/Night). HTTPS only, 15 s timeout, 64 KB response limit, at most every
// 30 minutes with back-off; offline or any error is silent and the normal wallpaper stays.
import Foundation
import AppKit

@MainActor final class WeatherService: ObservableObject {
    @Published private(set) var condition: WeatherCondition?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var lastError: String?
    private(set) var fetchState = WeatherFetchState()
    private weak var engine: LucidEngine?
    private var timer: Timer?
    private var inFlight = false
    var now: () -> Date = Date.init
    static let attributionURL = URL(string: "https://open-meteo.com/")
    private struct Saved: Codable { var cache: WeatherCache?; var fetch: WeatherFetchState }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral          // no cookies, no disk cache
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 20
        c.waitsForConnectivity = false
        c.httpAdditionalHeaders = ["User-Agent": Net.ua]
        return URLSession(configuration: c)
    }()

    init(engine: LucidEngine) {
        self.engine = engine
        if let d = try? Data(contentsOf: Paths.weather), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            fetchState = s.fetch
            if let c = s.cache { updatedAt = c.fetchedAt; condition = c.current(now: now()) }
        }
        engine.weatherNow = { [weak self] in self?.activeCondition }
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() } }
    }

    /// The condition rules react to: nil when the feature is off or the reading is older than 3 hours.
    var activeCondition: WeatherCondition? {
        guard Pref.weatherEnabled, let c = condition, let t = updatedAt else { return nil }
        return WeatherCache(condition: c, fetchedAt: t).current(now: now())
    }
    var needed: Bool { Pref.weatherEnabled && !(engine?.state.weather ?? [:]).isEmpty }

    func tick() {
        let before = activeCondition
        if let t = updatedAt, let c = condition, WeatherCache(condition: c, fetchedAt: t).current(now: now()) == nil { condition = nil }
        if before != activeCondition { engine?.weatherDidChange() }
        guard needed, !inFlight, WeatherPolicy.shouldFetch(fetchState, now: now()) else { return }
        Task { await fetch(url: WeatherRequest.url(latitude: Self.coordinates().0, longitude: Self.coordinates().1)) }
    }

    /// Approximate coordinates: the rounded fix the user already allowed for Day/Night, else the time zone's city.
    static func coordinates() -> (Double, Double) {
        if Pref.dayNightUseLocation, let l = Pref.lastLocation { return l }
        let tab = try? String(contentsOfFile: TimeZoneCoordinates.systemZoneTab, encoding: .utf8)
        let c = TimeZoneCoordinates.coordinates(for: .current, zoneTab: tab)
        return (c.latitude, c.longitude)
    }

    /// One request. Internal so the dev check can point it at an unreachable address to prove offline is quiet.
    func fetch(url: URL) async {
        inFlight = true
        defer { inFlight = false; save() }
        let t = now()
        guard url.scheme == "https" else { fetchState.recordFailure(at: t); lastError = "not HTTPS"; return }
        do {
            let (bytes, resp) = try await Self.session.bytes(from: url)
            guard let h = resp as? HTTPURLResponse, h.statusCode == 200, h.url?.scheme == "https", h.url?.host == url.host else {
                throw URLError(.badServerResponse) }
            var data = Data()
            for try await b in bytes {
                data.append(b)
                if data.count > WeatherParser.maxBytes { throw URLError(.dataLengthExceedsMaximum) }
            }
            guard let r = WeatherParser.parse(data) else { throw URLError(.cannotParseResponse) }
            fetchState.recordSuccess(at: t)
            lastError = nil
            let before = activeCondition
            condition = r.condition; updatedAt = t
            if before != activeCondition { engine?.weatherDidChange() }
        } catch {
            fetchState.recordFailure(at: t)
            lastError = (error as? URLError)?.code == .notConnectedToInternet ? "offline" : "unavailable"
        }
    }

    private func save() {
        let s = Saved(cache: condition.flatMap { c in updatedAt.map { WeatherCache(condition: c, fetchedAt: $0) } }, fetch: fetchState)
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: Paths.weather, options: .atomic) }
    }

    var statusText: String {
        guard Pref.weatherEnabled else { return "Off" }
        if !needed { return "On · set a weather wallpaper in Displays to start" }
        if let c = activeCondition, let t = updatedAt {
            return "\(c.label) · updated \(RelativeDateTimeFormatter().localizedString(for: t, relativeTo: now()))"
        }
        return lastError.map { "No reading yet (\($0)); your normal wallpaper stays" } ?? "Checking…"
    }
}
