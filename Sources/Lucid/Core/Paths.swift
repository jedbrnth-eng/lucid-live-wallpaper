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
    static let support = make(fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lucid", isDirectory: true))
    static let media = make(support.appendingPathComponent("Media", isDirectory: true))
    static let incoming = make(support.appendingPathComponent("Incoming", isDirectory: true))
    static let thumbs = make(support.appendingPathComponent("Thumbs", isDirectory: true))
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
