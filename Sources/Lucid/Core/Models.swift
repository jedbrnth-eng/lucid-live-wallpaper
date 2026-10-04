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
}

struct EngineState: Codable {
    var all: Assignment?
    var perScreen: [String: Assignment] = [:]
    var userPaused = false
}
