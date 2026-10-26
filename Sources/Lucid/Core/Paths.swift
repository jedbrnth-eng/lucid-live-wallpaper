// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// File locations under ~/Library/Application Support/Lucid.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// MARK: - Paths

enum Paths {
    static let fm = FileManager.default
    /// `LUCID_SUPPORT_DIR` lets a development build run against a throwaway folder instead of your real library.
    static let support = make(ProcessInfo.processInfo.environment["LUCID_SUPPORT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lucid", isDirectory: true))
    static let media = make(support.appendingPathComponent("Media", isDirectory: true))
    static let incoming = make(support.appendingPathComponent("Incoming", isDirectory: true))
    static let thumbs = make(support.appendingPathComponent("Thumbs", isDirectory: true))
    static let weCache = make(support.appendingPathComponent("WallpaperEngine", isDirectory: true))   // converted WE videos
    static let weIndex = support.appendingPathComponent("wallpaper-engine.json")
    static let library = support.appendingPathComponent("library.json")
    static let state = support.appendingPathComponent("state.json")
    static let status = support.appendingPathComponent("status.json")
    static let selftest = support.appendingPathComponent("selftest.json")
    static let favorites = support.appendingPathComponent("favorites.json")
    static let playlists = support.appendingPathComponent("playlists.json")
    static let aerialsRoot = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer")

    static func make(_ u: URL) -> URL {
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func safe(_ s: String) -> String {
        String(s.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }.prefix(80))
    }
}
