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
