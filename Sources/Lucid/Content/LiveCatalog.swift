// The curated Live 4K catalog (catalog.json) and playlists.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// MARK: - Curated live catalog (built by tools/build_catalog.py; every clip ffprobe-verified ≥4K)

enum LiveCatalog {
    static let bundled = Bundle.main.url(forResource: "catalog", withExtension: "json")
    static let userCopy = Paths.support.appendingPathComponent("catalog.json")

    static func load() -> [WallItem] {
        // Prefer the newer of the user copy and the bundled copy.
        var best: (Date, Data)?
        for u in [userCopy, bundled].compactMap({ $0 }) {
            guard let d = try? Data(contentsOf: u),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            let g = ISO8601DateFormatter().date(from: j["generated"] as? String ?? "") ?? .distantPast
            if best == nil || g > best!.0 { best = (g, d) }
        }
        guard let data = best?.1, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = j["items"] as? [[String: Any]] else { return [] }
        return rows.compactMap { r in
            if (r["needsTranscode"] as? Bool ?? false) && Transcoder.ffmpeg == nil { return nil }
            guard let id = r["id"] as? String, let url = r["url"] as? String,
                  let w = r["width"] as? Int, let h = r["height"] as? Int else { return nil }
            let lic = [(r["license"] as? String), ((r["creditFull"] as? String) ?? (r["credit"] as? String)).map { "Credit: \($0)" }].compactMap { $0 }.joined(separator: " · ")
            var it = WallItem(id: "live:\(id)", source: .live, kind: .video, title: r["title"] as? String ?? id, width: w, height: h,
                              thumbURL: r["thumb"] as? String, previewURL: url, downloadURL: url, pageURL: r["page"] as? String,
                              author: r["collection"] as? String, license: lic, category: r["tag"] as? String, fileExt: r["fileExt"] as? String ?? "mp4",
                              bytes: (r["bytes"] as? Int).map(Int64.init))
            it.duration = r["duration"] as? Double
            it.codec = r["codec"] as? String
            it.termsURL = r["licenseURL"] as? String
            it.creditFull = r["creditFull"] as? String ?? r["credit"] as? String
            return it
        }
    }
}

struct Playlist: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var items: [WallItem] = []
    var shuffle = true
    var minutes = 60
}
