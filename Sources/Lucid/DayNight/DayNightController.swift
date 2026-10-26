// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Keeps the day/night phase current: wakes at the next sunrise/sunset (or manual time), and re-checks on wake
// from sleep, time zone or clock changes and every 10 minutes. Location is used only if the user turns it on;
// otherwise coordinates come from the Mac's time zone (Asia/Bangkok -> Bangkok).
import Foundation
import AppKit
import CoreLocation

@MainActor final class DayNightController: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var phase: DayPhase = .day
    @Published private(set) var nextChange: Date?
    @Published private(set) var sourceText = ""
    private weak var engine: WallpaperEngine?
    private var timer: Timer?
    private var safety: Timer?
    private var observers: [NSObjectProtocol] = []
    private var location: CLLocationManager?
    var now: () -> Date = Date.init

    init(engine: WallpaperEngine) {
        self.engine = engine
        super.init()
        engine.phase = { [weak self] in self?.phase ?? .day }
        phase = schedule().phase(at: now())
        let wnc = NSWorkspace.shared.notificationCenter
        observers.append(wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() } })
        for n in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange, .NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { NSTimeZone.resetSystemTimeZone(); self?.evaluate() } })
        }
        safety = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.evaluate() } }
        if Pref.dayNightUseLocation { requestLocation() }
        evaluate()
    }

    func schedule() -> DayNightSchedule { make().0 }

    private func make() -> (DayNightSchedule, String) {
        let tz = TimeZone.current
        if Pref.dayNightManual {
            return (DayNightSchedule(mode: .manual(dayStartMinute: Pref.dayStartMinute, nightStartMinute: Pref.nightStartMinute), timeZone: tz), "Manual times")
        }
        if Pref.dayNightUseLocation, let (lat, lon) = Pref.lastLocation {
            return (DayNightSchedule(mode: .sun(latitude: lat, longitude: lon), timeZone: tz),
                    String(format: "Sunrise/sunset at your location (%.2f, %.2f)", lat, lon))
        }
        let tab = try? String(contentsOfFile: TimeZoneCoordinates.systemZoneTab, encoding: .utf8)
        let c = TimeZoneCoordinates.coordinates(for: tz, zoneTab: tab)
        let city = tz.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? tz.identifier
        return (DayNightSchedule(mode: .sun(latitude: c.latitude, longitude: c.longitude), timeZone: tz),
                c.approximate ? "Sunrise/sunset estimated from your time zone offset" : "Sunrise/sunset for \(city) (from your time zone)")
    }

    /// Today's sunrise and sunset in the current mode, for display.
    func todayTimes() -> (Date, Date)? {
        let s = schedule()
        if case .normal(let r, let t)? = s.sunEvent(onLocalDayOf: now()) { return (r, t) }
        return nil
    }

    func evaluate() {
        let (s, text) = make()
        sourceText = text
        let t = now()
        let p = s.phase(at: t)
        let changed = p != phase
        phase = p
        nextChange = s.nextChange(after: t)
        timer?.invalidate()
        if let n = nextChange {
            // +1 s so we land just after the boundary; cap so a long sleep can't leave us stale.
            let wait = min(max(1, n.timeIntervalSince(t) + 1), 6 * 3600)
            timer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.evaluate() } }
        }
        if changed { engine?.phaseDidChange() }
    }

    // MARK: Location (only when the user turns it on)

    func requestLocation() {
        if location == nil { let m = CLLocationManager(); m.delegate = self; m.desiredAccuracy = kCLLocationAccuracyKilometer; location = m }
        location?.requestWhenInUseAuthorization()
        location?.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in Pref.lastLocation = (c.latitude, c.longitude); self.evaluate() }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.evaluate() }   // falls back to time-zone coordinates
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorized { manager.requestLocation() }
        }
    }
}
