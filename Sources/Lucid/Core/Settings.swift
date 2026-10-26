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
    static var pauseOnBattery: Bool { get { d.object(forKey: "pauseOnBattery") as? Bool ?? false } set { d.set(newValue, forKey: "pauseOnBattery") } }
    static var pauseLowPower: Bool { get { d.object(forKey: "pauseLowPower") as? Bool ?? true } set { d.set(newValue, forKey: "pauseLowPower") } }
    static var pauseWhenCovered: Bool { get { d.object(forKey: "pauseWhenCovered") as? Bool ?? true } set { d.set(newValue, forKey: "pauseWhenCovered") } }
    static var rotateMinutes: Int { get { d.integer(forKey: "rotateMinutes") } set { d.set(newValue, forKey: "rotateMinutes") } }
    static var writeStatus: Bool { d.bool(forKey: "writeStatus") }
    static var speed: Double { get { d.object(forKey: "speed") as? Double ?? 1.0 } set { d.set(newValue, forKey: "speed") } }
    static var fillScreen: Bool { get { d.object(forKey: "fillScreen") as? Bool ?? true } set { d.set(newValue, forKey: "fillScreen") } }
    static var dim: Double { get { d.double(forKey: "dim") } set { d.set(newValue, forKey: "dim") } }
    static var watchDownloads: Bool { get { d.bool(forKey: "watchDownloads") } set { d.set(newValue, forKey: "watchDownloads") } }
    static var activePlaylist: String? { get { d.string(forKey: "activePlaylist") } set { d.set(newValue, forKey: "activePlaylist") } }

    // Wallpaper Engine library (plain paths: Lucid is not sandboxed, so no security-scoped bookmarks are needed)
    static var weFolders: [String] { get { d.stringArray(forKey: "weFolders") ?? [] } set { d.set(newValue, forKey: "weFolders") } }
    static var weScenePreviews: Bool { get { d.bool(forKey: "weScenePreviews") } set { d.set(newValue, forKey: "weScenePreviews") } }

    // Audio reactive (off by default)
    static var audioReactive: Bool { get { d.bool(forKey: "audioReactive") } set { d.set(newValue, forKey: "audioReactive") } }
    static var audioSensitivity: Double { get { d.object(forKey: "audioSensitivity") as? Double ?? 1.0 } set { d.set(newValue, forKey: "audioSensitivity") } }

    // Day/Night
    static var dayNightManual: Bool { get { d.bool(forKey: "dayNightManual") } set { d.set(newValue, forKey: "dayNightManual") } }
    static var dayNightUseLocation: Bool { get { d.bool(forKey: "dayNightUseLocation") } set { d.set(newValue, forKey: "dayNightUseLocation") } }
    static var dayStartMinute: Int { get { d.object(forKey: "dayStartMinute") as? Int ?? 7 * 60 } set { d.set(newValue, forKey: "dayStartMinute") } }
    static var nightStartMinute: Int { get { d.object(forKey: "nightStartMinute") as? Int ?? 19 * 60 } set { d.set(newValue, forKey: "nightStartMinute") } }
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
