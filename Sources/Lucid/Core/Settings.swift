// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// User preferences and Keychain storage for optional API keys.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// MARK: - Settings

enum Pref {
    static let d = UserDefaults.standard
    /// Missing key -> default. `bool(forKey:)`/`integer(forKey:)` also accept "YES"/"5" given as launch arguments.
    private static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
    private static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) == nil ? def : d.integer(forKey: k) }
    static var pauseOnBattery: Bool { get { bool("pauseOnBattery", false) } set { d.set(newValue, forKey: "pauseOnBattery") } }
    static var pauseLowPower: Bool { get { bool("pauseLowPower", true) } set { d.set(newValue, forKey: "pauseLowPower") } }
    static var pauseWhenCovered: Bool { get { bool("pauseWhenCovered", true) } set { d.set(newValue, forKey: "pauseWhenCovered") } }
    /// Pause on battery below this charge (0 = off).
    static var batteryBelowPercent: Int { get { int("batteryBelowPercent", 20) } set { d.set(newValue, forKey: "batteryBelowPercent") } }
    /// Pause at this thermal pressure or above (-1 = off). Default: serious.
    static var thermalLimitRaw: Int { get { int("thermalLimit", ThermalLevel.serious.rawValue) } set { d.set(newValue, forKey: "thermalLimit") } }
    static var thermalLimit: ThermalLevel? { ThermalLevel(rawValue: thermalLimitRaw) }
    /// Pause while the whole Mac's CPU use averages above this over 30 s (0 = off).
    static var cpuAbovePercent: Int { get { d.integer(forKey: "cpuAbovePercent") } set { d.set(newValue, forKey: "cpuAbovePercent") } }
    /// Release players after this many minutes of pause (0 = never).
    static var releaseAfterMinutes: Int { get { int("releaseAfterMinutes", 5) } set { d.set(newValue, forKey: "releaseAfterMinutes") } }
    static var rotateMinutes: Int { get { d.integer(forKey: "rotateMinutes") } set { d.set(newValue, forKey: "rotateMinutes") } }
    static var writeStatus: Bool { d.bool(forKey: "writeStatus") }
    static var speed: Double { get { d.object(forKey: "speed") as? Double ?? 1.0 } set { d.set(newValue, forKey: "speed") } }
    static var fillScreen: Bool { get { bool("fillScreen", true) } set { d.set(newValue, forKey: "fillScreen") } }
    static var dim: Double { get { d.double(forKey: "dim") } set { d.set(newValue, forKey: "dim") } }
    /// Import "in place": point at your file instead of copying it into Lucid's Media folder (off = copy, the default).
    static var importInPlace: Bool { get { d.bool(forKey: "importInPlace") } set { d.set(newValue, forKey: "importInPlace") } }
    static var watchDownloads: Bool { get { d.bool(forKey: "watchDownloads") } set { d.set(newValue, forKey: "watchDownloads") } }
    static var activePlaylist: String? { get { d.string(forKey: "activePlaylist") } set { d.set(newValue, forKey: "activePlaylist") } }

    // Audio reactive (off by default)
    static var audioReactive: Bool { get { d.bool(forKey: "audioReactive") } set { d.set(newValue, forKey: "audioReactive") } }
    static var audioSensitivity: Double { get { d.object(forKey: "audioSensitivity") as? Double ?? 1.0 } set { d.set(newValue, forKey: "audioSensitivity") } }

    /// Opt-in daily check of GitHub's latest release (no telemetry, nothing installed automatically).
    static var updateCheck: Bool { get { d.bool(forKey: "updateCheck") } set { d.set(newValue, forKey: "updateCheck") } }
    static var lastUpdateCheck: Date? { get { d.object(forKey: "lastUpdateCheck") as? Date } set { d.set(newValue, forKey: "lastUpdateCheck") } }

    // Weather wallpapers (off by default; see WeatherService)
    static var weatherEnabled: Bool { get { d.bool(forKey: "weatherEnabled") } set { d.set(newValue, forKey: "weatherEnabled") } }

    // Day/Night
    static var dayNightManual: Bool { get { d.bool(forKey: "dayNightManual") } set { d.set(newValue, forKey: "dayNightManual") } }
    static var dayNightUseLocation: Bool { get { d.bool(forKey: "dayNightUseLocation") } set { d.set(newValue, forKey: "dayNightUseLocation") } }
    static var dayStartMinute: Int { get { int("dayStartMinute", 7 * 60) } set { d.set(newValue, forKey: "dayStartMinute") } }
    static var nightStartMinute: Int { get { int("nightStartMinute", 19 * 60) } set { d.set(newValue, forKey: "nightStartMinute") } }
    /// Last location fix, rounded to ~1 km, so Auto keeps working offline and after relaunch.
    static var lastLocation: (Double, Double)? {
        get { guard let a = d.array(forKey: "lastLocation") as? [Double], a.count == 2 else { return nil }; return (a[0], a[1]) }
        set { d.set(newValue.map { [($0.0 * 100).rounded() / 100, ($0.1 * 100).rounded() / 100] }, forKey: "lastLocation") }
    }
}

// MARK: - Keychain (API keys typed by the user into Settings)

enum Keychain {
    static let service = "com.jedbrn.lucid"
    static func get(_ k: KeyName) -> String? {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                  kSecAttrAccount: k.rawValue, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty ?? true) ? nil : s
    }
    static func set(_ k: KeyName, _ v: String) {
        let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: k.rawValue]
        SecItemDelete(base as CFDictionary)
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var add = base; add[kSecValueData] = Data(t.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
