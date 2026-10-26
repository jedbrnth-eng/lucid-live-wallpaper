// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Wallpaper items, sources, display assignments and saved engine state.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// MARK: - Models

enum Kind: String, Codable { case video, image }

enum KeyName: String, CaseIterable { case pixabay
    var label: String { "Pixabay" }
    var signupURL: URL { URL(string: "https://pixabay.com/api/docs/")! }
}

enum Source: String, Codable, CaseIterable, Identifiable {
    case aerials, live, pixabayVideo, nasa, wikimedia, local
    var id: String { rawValue }
    static let discoverable: [Source] = [.aerials, .live, .pixabayVideo, .nasa, .wikimedia]

    var label: String {
        switch self {
        case .aerials: return "Apple Aerials"
        case .live: return "Live 4K"
        case .pixabayVideo: return "Pixabay 4K Video"
        case .nasa: return "NASA 4K Space"
        case .wikimedia: return "Wikimedia 4K Photos"
        case .local: return "My Files"
        }
    }
    var icon: String {
        switch self {
        case .aerials: return "airplane"
        case .live: return "sparkles"
        case .pixabayVideo: return "play.rectangle.on.rectangle"
        case .nasa: return "moon.stars"
        case .wikimedia: return "building.columns"
        case .local: return "folder"
        }
    }
    var blurb: String {
        switch self {
        case .live: return "Moving 4K wallpapers — space from ESA/Webb, ESA/Hubble, ESO & NASA, plus nature/sky/ocean from Wikimedia Commons. Every clip checked ≥3840×2160; downloads are made to loop seamlessly. Credit & license on each."
        case .aerials: return "Apple's own 4K aerial films (3840×2160 HEVC) — the same ones macOS uses. Free, no account."
        case .pixabayVideo: return "Free stock video. Only clips whose largest file is ≥3840×2160 are shown. Needs a free Pixabay key."
        case .nasa: return "NASA Image Library — space & Earth photos, only originals ≥3840×2160. Free, no account. Generally public domain."
        case .wikimedia: return "Wikimedia Commons, filtered to ≥3840×2160 landscape images. Free, no account. Per-image license shown."
        case .local: return "Your own files."
        }
    }
    var needsKey: KeyName? {
        switch self {
        case .pixabayVideo: return .pixabay
        default: return nil
        }
    }
    var licenseURL: URL? {
        switch self {
        case .nasa: return URL(string: "https://www.nasa.gov/nasa-brand-center/images-and-media/")
        case .live: return nil  // per-item termsURL
        case .pixabayVideo: return URL(string: "https://pixabay.com/service/license-summary/")
        case .wikimedia: return URL(string: "https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia")
        default: return nil
        }
    }
    var quickQueries: [String] {
        switch self {
        case .aerials, .live: return []
        case .wikimedia: return ["Night city", "Neon", "Mountains", "Ocean", "Milky Way", "Bangkok", "Forest", "Aurora"]
        case .nasa: return ["Nebula", "Galaxy", "Earth at night", "Aurora", "Saturn", "Jupiter", "Webb", "Hubble"]
        default: return ["Neon city", "Night", "Rain", "Ocean", "Mountains", "Space", "Abstract", "Smoke", "Forest", "Clouds"]
        }
    }
}

struct WallItem: Codable, Identifiable, Hashable {
    var id: String
    var source: Source
    var kind: Kind
    var title: String
    var width: Int
    var height: Int
    var thumbURL: String?
    var previewURL: String?      // small video / large image for the detail view
    var downloadURL: String?     // the ≥4K file
    var pageURL: String?
    var author: String?
    var license: String?
    var category: String?
    var fileExt: String?
    var localPath: String?
    var thumbPath: String?
    var bytes: Int64?
    var addedAt: Date?
    var duration: Double?
    var codec: String?
    var termsURL: String?
    var creditFull: String?
    var lastAppliedAt: Date?
    var tags: [String]?
    var options: WallpaperOptions?   // per-wallpaper fit / crop focus / speed (1.3.0+)
    var referenced: Bool?            // true = imported "in place": Lucid points at your file and never deletes it
    var is4K: Bool { max(width, height) >= 3840 && min(width, height) >= 2160 }
    var resLabel: String {
        let m = max(width, height)
        if m >= 7680 { return "8K" }
        if m >= 6000 { return "6K" }
        if m >= 5120 { return "5K" }
        if is4K { return "4K" }
        return width > 0 ? "\(width)×\(height)" : "?"
    }
    var isLocalReady: Bool { localPath.map { FileManager.default.fileExists(atPath: $0) } ?? false }
}

struct Assignment: Codable, Equatable {
    var itemID: String
    var title: String
    var path: String
    var kind: Kind
    var reactive: ReactiveOptions?   // optional audio-reactive look for this wallpaper
    var options: WallpaperOptions?   // optional per-wallpaper fit / crop focus / speed (1.3.0+)

    /// Same media on screen (ignores look options, which are updated in place without reloading).
    func sameMedia(_ o: Assignment) -> Bool { path == o.path && kind == o.kind }
}

enum FitMode: String, Codable, CaseIterable { case fill, fit, stretch }

/// Per-wallpaper display options. Every field is optional: nil = use the app-wide setting.
struct WallpaperOptions: Codable, Equatable, Hashable {
    var fit: FitMode?
    var focusX: Double?   // 0 = left edge, 1 = right edge (fill only)
    var focusY: Double?   // 0 = top, 1 = bottom (fill only)
    var speed: Double?

    init(fit: FitMode? = nil, focusX: Double? = nil, focusY: Double? = nil, speed: Double? = nil) {
        self.fit = fit; self.focusX = focusX; self.focusY = focusY; self.speed = speed
    }
    /// Lenient: an unknown or malformed field is dropped on its own; it never makes the wallpaper unreadable.
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { self.init(); return }
        self.init(fit: (try? c.decodeIfPresent(FitMode.self, forKey: .fit)) ?? nil,
                  focusX: (try? c.decodeIfPresent(Double.self, forKey: .focusX)) ?? nil,
                  focusY: (try? c.decodeIfPresent(Double.self, forKey: .focusY)) ?? nil,
                  speed: (try? c.decodeIfPresent(Double.self, forKey: .speed)) ?? nil)
    }
    var isDefault: Bool { fit == nil && focusX == nil && focusY == nil && speed == nil }
    func effectiveSpeed(default d: Double) -> Double { min(4, max(0.25, speed ?? d)) }
    func effectiveFit(defaultFill: Bool) -> FitMode { fit ?? (defaultFill ? .fill : .fit) }
}

/// A Day/Night assignment: one wallpaper between sunrise and sunset, another the rest of the time.
struct DayNightRule: Codable, Equatable {
    var day: Assignment
    var night: Assignment
    func pick(_ p: DayPhase) -> Assignment { p == .day ? day : night }
}

struct EngineState: Codable {
    var all: Assignment?
    var perScreen: [String: Assignment] = [:]
    var userPaused = false
    var dayNight: [String: DayNightRule]?   // key: display key, or "*" for all displays. Optional so old state.json still decodes.
    static let allKey = "*"
}

struct Playlist: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var items: [WallItem] = []
    var shuffle = true
    var minutes = 60
    var times: [Int]?   // optional: change at these minutes after local midnight instead of every `minutes` (1.3.0+)
}

// MARK: - Loading saved data (library.json, favorites.json, playlists.json, state.json)

// Saved files can hold entries this version no longer understands (a removed source or kind, e.g. from a
// development build, or a newer Lucid). Each entry is decoded on its own, so only that entry is dropped.

enum SavedData {
    static func items(_ d: Data) -> [WallItem] { (try? JSONDecoder().decode(LossyArray<WallItem>.self, from: d))?.values ?? [] }
    static func playlists(_ d: Data) -> [Playlist] { (try? JSONDecoder().decode(LossyArray<Playlist>.self, from: d))?.values ?? [] }
    static func state(_ d: Data) -> EngineState? { try? JSONDecoder().decode(EngineState.self, from: d) }
}

struct LossyArray<T: Decodable>: Decodable {
    var values: [T]
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [T] = []
        while !c.isAtEnd {
            if let v = try? c.decode(T.self) { out.append(v) } else { _ = try c.decode(Skip.self) }   // Skip moves past the bad entry
        }
        values = out
    }
}

struct LossyDictionary<T: Decodable>: Decodable {
    var values: [String: T]
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        var out: [String: T] = [:]
        for k in c.allKeys { if let v = try? c.decode(T.self, forKey: k) { out[k.stringValue] = v } }
        values = out
    }
}

extension Playlist {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        items = try c.decode(LossyArray<WallItem>.self, forKey: .items).values
        shuffle = try c.decode(Bool.self, forKey: .shuffle)
        minutes = try c.decode(Int.self, forKey: .minutes)
        times = (try? c.decodeIfPresent([Int].self, forKey: .times)) ?? nil
    }
}

extension EngineState {
    /// Assignments or Day/Night rules that no longer decode (e.g. a removed wallpaper kind) are dropped; the rest is kept.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        all = (try? c.decodeIfPresent(Assignment.self, forKey: .all)) ?? nil
        perScreen = ((try? c.decodeIfPresent(LossyDictionary<Assignment>.self, forKey: .perScreen)) ?? nil)?.values ?? [:]
        userPaused = ((try? c.decodeIfPresent(Bool.self, forKey: .userPaused)) ?? nil) ?? false
        dayNight = ((try? c.decodeIfPresent(LossyDictionary<DayNightRule>.self, forKey: .dayNight)) ?? nil)?.values
    }
}
