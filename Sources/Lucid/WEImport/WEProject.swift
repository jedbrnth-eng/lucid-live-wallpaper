// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Wallpaper Engine importer: reads the user's own Wallpaper Engine folders (project.json per item)
// and classifies each item by what Lucid can honestly play on a Mac. UI-free, unit-tested.
//
// project.json shape (documented at https://docs.wallpaperengine.io/en/web/first/gettingstarted.html and seen in
// public samples such as github.com/juncaixinchi/Wallpaper-Engine/blob/master/project.json):
//   { "title": "...", "type": "video" | "scene" | "web" | "application" (case varies, e.g. "Video", "Web"),
//     "file": "entry file", "preview": "preview.jpg|gif", "tags": [..], "description": "...",
//     "workshopid": "123" or 123, "general": { "properties": { "name": { "type": .., "value": .. } } } }
// Lucid only keeps references to these files. It never copies or redistributes them.
import Foundation

enum WEType: String, Codable, CaseIterable {
    case video, scene, web, application, unknown
    var label: String {
        switch self {
        case .video: return "Video"
        case .scene: return "Scene"
        case .web: return "Web"
        case .application: return "Application"
        case .unknown: return "Other"
        }
    }
}

/// What Lucid can do with an item on macOS.
enum WESupport: String, Codable {
    case video        // plays natively (MP4/MOV) or after a one-time HEVC conversion (WebM etc.)
    case web          // HTML wallpaper in a WebKit window, best effort
    case unsupported  // scene (.pkg, Wallpaper Engine's own renderer), Windows application, or broken item
}

struct WEProject {
    var title: String?
    var type: WEType = .unknown
    var rawType: String?
    var file: String?
    var preview: String?
    var tags: [String] = []
    var description: String?
    var workshopID: String?
    /// Default user properties as `{ "name": { "value": x } }` JSON, the shape `applyUserProperties` expects.
    var userPropertiesJSON: String?

    static func parse(_ data: Data) throws -> WEProject {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "WEProject", code: 1, userInfo: [NSLocalizedDescriptionKey: "project.json is not an object"])
        }
        func str(_ k: String) -> String? {
            if let s = o[k] as? String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
            if let n = o[k] as? NSNumber { return n.stringValue }
            return nil
        }
        var p = WEProject()
        p.title = str("title")
        p.rawType = str("type")
        p.type = WEType(rawValue: (p.rawType ?? "").lowercased()) ?? .unknown
        p.file = str("file")
        p.preview = str("preview")
        p.tags = (o["tags"] as? [Any])?.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        p.description = str("description")
        p.workshopID = str("workshopid").flatMap { $0 == "0" ? nil : $0 }
        if let props = (o["general"] as? [String: Any])?["properties"] as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in props {
                guard let d = v as? [String: Any], d["type"] as? String != "group" else { continue }
                out[k] = ["value": d["value"] ?? NSNull()]
            }
            if let d = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) { p.userPropertiesJSON = String(data: d, encoding: .utf8) }
        }
        return p
    }
}

struct WEEntry: Codable, Equatable, Hashable {
    var id: String
    var workshopID: String?
    var title: String
    var type: WEType
    var support: WESupport
    var folder: String
    var mainFile: String?        // absolute path to the playable file (video or index.html); nil when unsupported
    var previewFile: String?     // still or animated preview shipped with the item
    var fallbackPreview: String? // scene only: animated preview (gif/video), a labelled stand-in, never the real thing
    var tags: [String]
    var description: String?
    var needsConversion: Bool    // video that AVFoundation can't play directly (WebM, MKV…)
    var note: String             // honest one-line label for the UI
    var userPropertiesJSON: String?
}

struct WECounts: Equatable { var video = 0, web = 0, unsupported = 0 }

struct WEScanResult {
    var entries: [WEEntry] = []
    var errors: [String] = []
    var counts: WECounts {
        var c = WECounts()
        for e in entries {
            switch e.support { case .video: c.video += 1; case .web: c.web += 1; case .unsupported: c.unsupported += 1 }
        }
        return c
    }
}

enum WEScanner {
    static let appID = "431960"
    static let nativeVideo: Set<String> = ["mp4", "mov", "m4v"]
    static let convertibleVideo: Set<String> = ["webm", "mkv", "avi", "wmv", "flv", "ogv", "mpg", "mpeg", "ts", "gif"]
    static let animatedPreview: Set<String> = ["gif", "mp4", "webm", "mov", "m4v"]

    /// Sub-paths that, when present under a chosen folder, hold Wallpaper Engine items.
    static let knownLayouts = [
        "steamapps/workshop/content/\(appID)", "workshop/content/\(appID)", "content/\(appID)", appID,
        "steamapps/common/wallpaper_engine/projects/myprojects", "common/wallpaper_engine/projects/myprojects",
        "wallpaper_engine/projects/myprojects", "projects/myprojects", "myprojects",
    ]

    /// Item folders under a root the user picked: the item itself, a known Steam/WE layout below it, or its subfolders.
    static func itemFolders(in root: URL) -> [URL] {
        let fm = FileManager.default
        func isDir(_ u: URL) -> Bool { var d: ObjCBool = false; return fm.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue }
        guard isDir(root) else { return [] }
        if fm.fileExists(atPath: root.appendingPathComponent("project.json").path) { return [root] }
        let containers = knownLayouts.map { root.appendingPathComponent($0, isDirectory: true) }.filter(isDir)
        var out: [URL] = []
        for c in containers.isEmpty ? [root] : containers {
            let subs = (try? fm.contentsOfDirectory(at: c, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            out += subs.filter { isDir($0) && fm.fileExists(atPath: $0.appendingPathComponent("project.json").path) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        return out
    }

    static func scan(roots: [URL]) -> WEScanResult {
        var r = WEScanResult()
        var seenIDs = Set<String>(), seenFolders = Set<String>()
        for root in roots {
            for folder in itemFolders(in: root.standardizedFileURL) {
                let key = folder.resolvingSymlinksInPath().standardizedFileURL.path
                guard seenFolders.insert(key).inserted else { continue }
                do {
                    let e = try entry(folder: folder)
                    guard seenIDs.insert(e.id).inserted else { continue }   // de-dupe by workshop id
                    r.entries.append(e)
                } catch {
                    r.errors.append("\(folder.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        return r
    }

    static func entry(folder: URL) throws -> WEEntry {
        let fm = FileManager.default
        let p = try WEProject.parse(Data(contentsOf: folder.appendingPathComponent("project.json")))
        func existing(_ name: String?) -> String? {
            guard let n = name, !n.contains("..") else { return nil }
            let u = folder.appendingPathComponent(n.replacingOccurrences(of: "\\", with: "/"))
            return fm.fileExists(atPath: u.path) ? u.path : nil
        }
        let id = p.workshopID.map { "we:" + $0 } ?? "we:local:" + stableHash(folder.standardizedFileURL.path)
        let title = p.title ?? niceFolderTitle(folder.lastPathComponent)
        let preview = existing(p.preview)
        var e = WEEntry(id: id, workshopID: p.workshopID, title: title, type: p.type, support: .unsupported,
                        folder: folder.path, mainFile: nil, previewFile: preview, fallbackPreview: nil, tags: p.tags,
                        description: p.description, needsConversion: false, note: "", userPropertiesJSON: p.userPropertiesJSON)
        switch p.type {
        case .video:
            if let f = existing(p.file) {
                let ext = (f as NSString).pathExtension.lowercased()
                if nativeVideo.contains(ext) { e.support = .video; e.mainFile = f; e.note = "Video · plays natively" }
                else if convertibleVideo.contains(ext) {
                    e.support = .video; e.mainFile = f; e.needsConversion = true
                    e.note = "Video · converted to HEVC on first use"
                } else { e.note = "Video format .\(ext) is not supported" }
            } else { e.note = "Video file missing from the folder" }
        case .web:
            if let f = existing(p.file ?? "index.html"), ["html", "htm"].contains((f as NSString).pathExtension.lowercased()) {
                e.support = .web; e.mainFile = f; e.note = "Web wallpaper · best effort (WebKit)"
            } else { e.note = "Web page missing from the folder" }
        case .scene:
            e.note = "Scene · needs Wallpaper Engine's own renderer, not available on Mac"
            if let pv = preview, animatedPreview.contains((pv as NSString).pathExtension.lowercased()) { e.fallbackPreview = pv }
        case .application:
            e.note = "Application · Windows program, cannot run on Mac"
        case .unknown:
            e.note = "Type “\(p.rawType ?? "none")” is not supported on Mac"
        }
        return e
    }

    /// "my-cool_loop" -> "My Cool Loop"
    static func niceFolderTitle(_ s: String) -> String {
        s.replacingOccurrences(of: #"[-_.]+"#, with: " ", options: .regularExpression)
            .split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// FNV-1a 64-bit, hex. Stable across launches (Swift's hashValue is not).
    static func stableHash(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    // MARK: Steam detection (read-only; Lucid never signs in to Steam or touches credentials)

    /// `"path"  "..."` values from Steam's libraryfolders.vdf, with VDF escapes (`\\`) undone.
    static func parseLibraryFolders(_ vdf: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #""path"\s+"((?:[^"\\]|\\.)*)""#) else { return [] }
        let ns = vdf as NSString
        return re.matches(in: vdf, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1)).replacingOccurrences(of: "\\\\", with: "\\")
        }
    }

    /// Wallpaper Engine folders that exist under the Mac Steam install (default library plus any extra libraries).
    static func detectSteamFolders(home: URL) -> [URL] {
        let fm = FileManager.default
        let steam = home.appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
        var libraries = [steam]
        if let vdf = try? String(contentsOf: steam.appendingPathComponent("steamapps/libraryfolders.vdf"), encoding: .utf8) {
            libraries += parseLibraryFolders(vdf).filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        var out: [URL] = [], seen = Set<String>()
        for lib in libraries {
            for sub in ["steamapps/workshop/content/\(appID)", "steamapps/common/wallpaper_engine/projects/myprojects"] {
                let u = lib.appendingPathComponent(sub, isDirectory: true)
                var d: ObjCBool = false
                if fm.fileExists(atPath: u.path, isDirectory: &d), d.boolValue, seen.insert(u.standardizedFileURL.path).inserted { out.append(u) }
            }
        }
        return out
    }
}

enum WESync {
    /// What changed between two scans, by id.
    static func diff(old: [WEEntry], new: [WEEntry]) -> (added: [WEEntry], removed: [WEEntry]) {
        let o = Set(old.map(\.id)), n = Set(new.map(\.id))
        return (new.filter { !o.contains($0.id) }, old.filter { !n.contains($0.id) })
    }
}
