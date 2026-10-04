// Lucid — 4K live-wallpaper app for macOS
// Native SwiftUI + AppKit. Build: ./build.sh
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

// MARK: - Networking

enum NetError: LocalizedError {
    case http(Int), badData, noKey
    var errorDescription: String? {
        switch self {
        case .http(let c): return c == 401 || c == 403 ? "The service rejected the API key (HTTP \(c))." : c == 429 ? "Rate limited by the service — try again in a minute." : "Server error (HTTP \(c))."
        case .badData: return "Unexpected response from the service."
        case .noKey: return "API key needed."
        }
    }
}

enum Net {
    static let ua = "Lucid/1.0 (macOS live wallpaper app; +https://github.com/jedbrnth-eng/lucid-live-wallpaper)"
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["User-Agent": ua]
        c.timeoutIntervalForRequest = 30
        c.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        return URLSession(configuration: c)
    }()
    static func json(_ url: URL, headers: [String: String] = [:]) async throws -> [String: Any] {
        var r = URLRequest(url: url)
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        let (d, resp) = try await session.data(for: r)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw NetError.http(h.statusCode) }
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw NetError.badData }
        return j
    }
    static func url(_ base: String, _ q: [String: String]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = q.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url!
    }
}

// MARK: - Providers (every provider enforces the ≥3840×2160 bar)

struct ResultPage { var items: [WallItem]; var next: Int?; var rejected: Int }

enum Providers {
    static func is4KLandscape(_ w: Int, _ h: Int) -> Bool { w >= 3840 && h >= 2160 && w >= h }

    // Apple Aerials — read the system catalog macOS already ships.
    static func aerials() -> [WallItem] {
        let root = Paths.aerialsRoot
        guard let d = try? Data(contentsOf: root.appendingPathComponent("entries.json")),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let assets = j["assets"] as? [[String: Any]] else { return [] }
        let strings = (NSDictionary(contentsOf: root.appendingPathComponent("TVIdleScreenStrings.bundle/en.lproj/Localizable.nocache.strings")) as? [String: String]) ?? [:]
        var cats: [String: String] = [:]
        for c in (j["categories"] as? [[String: Any]]) ?? [] {
            if let id = c["id"] as? String, let k = c["localizedNameKey"] as? String { cats[id] = strings[k] ?? k }
        }
        var seen = Set<String>()
        return assets.compactMap { a -> WallItem? in
            guard let id = a["id"] as? String, let url = a["url-4K-SDR-240FPS"] as? String, url.hasPrefix("https://"),
                  !seen.contains(id) else { return nil }
            seen.insert(id)
            let place = strings[(a["localizedNameKey"] as? String) ?? ""]
            let label = (a["accessibilityLabel"] as? String) ?? place ?? "Aerial"
            let cat = ((a["categories"] as? [String]) ?? []).compactMap { cats[$0] }.first
            var it = WallItem(id: "aerials:\(id)", source: .aerials, kind: .video, title: label, width: 3840, height: 2160,
                              thumbURL: a["previewImage"] as? String, previewURL: url, downloadURL: url, pageURL: nil,
                              author: place.map { "Apple · \($0)" } ?? "Apple",
                              license: "Apple macOS Aerial — personal use on this Mac; don't redistribute",
                              category: cat, fileExt: "mov")
            let cached = root.appendingPathComponent("4KSDR240FPS/\(id).mov").path
            if FileManager.default.isReadableFile(atPath: cached) { it.localPath = cached }
            return it
        }
    }

    static func fetch(_ s: Source, query: String, page: Int, featured: Bool) async throws -> ResultPage {
        switch s {
        case .wikimedia: return try await wikimedia(query, offset: page, featured: featured)
        case .nasa: return try await nasa(query, page: page)
        case .pixabayVideo: return try await pixabayVideo(query, page: page)
        default: return ResultPage(items: [], next: nil, rejected: 0)
        }
    }

    static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func wikimedia(_ q: String, offset: Int, featured: Bool) async throws -> ResultPage {
        var terms = q.trimmingCharacters(in: .whitespaces)
        if featured || terms.isEmpty { terms += " incategory:\"Featured_pictures_on_Wikimedia_Commons\"" }
        terms += " filew:>3839 fileh:>2159 filetype:bitmap"
        let u = Net.url("https://commons.wikimedia.org/w/api.php", [
            "action": "query", "format": "json", "generator": "search", "gsrnamespace": "6",
            "gsrsearch": terms, "gsrlimit": "40", "gsroffset": "\(max(0, offset))", "prop": "imageinfo",
            "iiprop": "url|size|mime|extmetadata", "iiurlwidth": "640",
            "iiextmetadatafilter": "LicenseShortName|Artist|ObjectName|Credit"])
        let j = try await Net.json(u)
        let pages = ((j["query"] as? [String: Any])?["pages"] as? [String: Any]) ?? [:]
        var rows: [(Int, WallItem)] = []
        var rejected = 0
        for (_, v) in pages {
            guard let p = v as? [String: Any], let ii = (p["imageinfo"] as? [[String: Any]])?.first,
                  let w = ii["width"] as? Int, let h = ii["height"] as? Int, let url = ii["url"] as? String else { continue }
            let mime = ii["mime"] as? String ?? ""
            guard is4KLandscape(w, h), mime == "image/jpeg" || mime == "image/png" else { rejected += 1; continue }
            let meta = ii["extmetadata"] as? [String: Any] ?? [:]
            func m(_ k: String) -> String? { ((meta[k] as? [String: Any])?["value"] as? String).map(stripHTML) }
            var title = (p["title"] as? String ?? "Image").replacingOccurrences(of: "File:", with: "")
            if let dot = title.lastIndex(of: ".") { title = String(title[..<dot]) }
            let thumb = ii["thumburl"] as? String
            let big = thumb?.replacingOccurrences(of: "/640px-", with: "/1920px-")
            let item = WallItem(id: "wikimedia:\(p["pageid"] as? Int ?? 0)", source: .wikimedia, kind: .image,
                                title: m("ObjectName") ?? title, width: w, height: h, thumbURL: thumb, previewURL: big,
                                downloadURL: url, pageURL: ii["descriptionurl"] as? String,
                                author: m("Artist").map { String($0.prefix(80)) }, license: m("LicenseShortName") ?? "See file page",
                                category: nil, fileExt: mime == "image/png" ? "png" : "jpg", bytes: nil)
            rows.append((p["index"] as? Int ?? 0, item))
        }
        let next = ((j["continue"] as? [String: Any])?["gsroffset"] as? Int)
        return ResultPage(items: rows.sorted { $0.0 < $1.0 }.map { $0.1 }, next: next, rejected: rejected)
    }

    static func nasa(_ q: String, page: Int) async throws -> ResultPage {
        let u = Net.url("https://images-api.nasa.gov/search", ["q": q.isEmpty ? "nebula" : q, "media_type": "image",
                                                               "page_size": "100", "page": "\(page)"])
        let j = try await Net.json(u)
        let col = j["collection"] as? [String: Any] ?? [:]
        var items: [WallItem] = []; var rejected = 0
        for it in (col["items"] as? [[String: Any]]) ?? [] {
            guard let d = (it["data"] as? [[String: Any]])?.first, let nid = d["nasa_id"] as? String else { continue }
            let links = (it["links"] as? [[String: Any]]) ?? []
            guard let canon = links.first(where: { ($0["rel"] as? String) == "canonical" }),
                  let w = canon["width"] as? Int, let h = canon["height"] as? Int, let href = canon["href"] as? String,
                  is4KLandscape(w, h), ["jpg", "jpeg", "png"].contains(URL(string: href)?.pathExtension.lowercased() ?? "")
            else { rejected += 1; continue }
            let alt = links.first { ($0["rel"] as? String) == "alternate" && (($0["width"] as? Int) ?? 0) >= 1280 }?["href"] as? String
            let thumb = links.first { ($0["rel"] as? String) == "preview" }?["href"] as? String
            let enc = nid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nid
            items.append(WallItem(id: "nasa:\(nid)", source: .nasa, kind: .image, title: (d["title"] as? String) ?? nid,
                                  width: w, height: h, thumbURL: thumb, previewURL: alt ?? thumb, downloadURL: href,
                                  pageURL: "https://images.nasa.gov/details/\(enc)",
                                  author: [d["center"] as? String, d["photographer"] as? String].compactMap { $0 }.joined(separator: " · ").ifEmpty("NASA"),
                                  license: "NASA media — generally public domain; credit NASA, no endorsement implied",
                                  fileExt: URL(string: href)?.pathExtension.lowercased() ?? "jpg",
                                  bytes: (canon["size"] as? Int).map(Int64.init)))
        }
        let hasNext = ((col["links"] as? [[String: Any]]) ?? []).contains { ($0["rel"] as? String) == "next" }
        return ResultPage(items: items, next: hasNext ? page + 1 : nil, rejected: rejected)
    }

    static func pixabayVideo(_ q: String, page: Int) async throws -> ResultPage {
        guard let key = Keychain.get(.pixabay) else { throw NetError.noKey }
        let u = Net.url("https://pixabay.com/api/videos/", ["key": key, "q": q, "per_page": "50", "page": "\(page)",
                                                            "safesearch": "true", "min_width": "3840", "min_height": "2160"])
        let j = try await Net.json(u)
        var items: [WallItem] = []; var rejected = 0
        for v in (j["hits"] as? [[String: Any]]) ?? [] {
            let vids = v["videos"] as? [String: Any] ?? [:]
            let large = vids["large"] as? [String: Any] ?? [:]
            let w = large["width"] as? Int ?? 0, h = large["height"] as? Int ?? 0
            guard is4KLandscape(w, h), let url = large["url"] as? String, !url.isEmpty else { rejected += 1; continue }
            let medium = vids["medium"] as? [String: Any] ?? [:]
            let small = vids["small"] as? [String: Any] ?? [:]
            let id = v["id"] as? Int ?? 0
            let tags = (v["tags"] as? String ?? "").split(separator: ",").prefix(3).map { $0.trimmingCharacters(in: .whitespaces).capitalized }
            items.append(WallItem(id: "pixabayv:\(id)", source: .pixabayVideo, kind: .video,
                                  title: tags.isEmpty ? "Pixabay video \(id)" : tags.joined(separator: " · "),
                                  width: w, height: h, thumbURL: (large["thumbnail"] as? String) ?? (medium["thumbnail"] as? String),
                                  previewURL: (small["url"] as? String) ?? (medium["url"] as? String), downloadURL: url,
                                  pageURL: v["pageURL"] as? String, author: v["user"] as? String,
                                  license: "Pixabay Content License — free use, no attribution required", fileExt: "mp4",
                                  bytes: (large["size"] as? Int).map(Int64.init)))
        }
        let total = j["totalHits"] as? Int ?? 0
        return ResultPage(items: items, next: page * 50 < min(total, 500) ? page + 1 : nil, rejected: rejected)
    }
}

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

// MARK: - Seamless loop maker
// Most source clips are not authored as loops: the last frame jumps back to the first.
// We build a new file where the tail cross-fades into the head, so playback wraps invisibly.
// Audio is dropped (wallpapers are muted anyway, and soundtrack licences often differ from the footage).

final class ExportBox: @unchecked Sendable { let session: AVAssetExportSession; init(_ s: AVAssetExportSession) { session = s } }

enum Transcoder {
    static let ffmpeg: String? = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// WebM/VP9/AV1 -> HEVC MP4 (hardware encoder, no audio) so AVFoundation can play it.
    static func toHEVC(_ src: URL, _ dst: URL) async throws {
        guard let ff = ffmpeg else { throw NSError(domain: "tx", code: 1, userInfo: [NSLocalizedDescriptionKey: "Needs ffmpeg (brew install ffmpeg) to convert WebM"]) }
        try? FileManager.default.removeItem(at: dst)
        let code: Int32 = try await withCheckedThrowingContinuation { c in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ff)
            p.arguments = ["-v", "error", "-y", "-i", src.path, "-map", "0:v:0", "-an",
                           "-vf", "scale='min(3840,iw)':-2:flags=lanczos,format=yuv420p",
                           "-c:v", "hevc_videotoolbox", "-q:v", "65", "-tag:v", "hvc1", "-movflags", "+faststart", dst.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { c.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { c.resume(throwing: error) }
        }
        guard code == 0, FileManager.default.fileExists(atPath: dst.path) else {
            throw NSError(domain: "tx", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "ffmpeg conversion failed (\(code))"]) }
    }
}

enum LoopMaker {
    static let fade = 1.5

    static func make(_ src: URL, to dst: URL) async throws {
        let asset = AVURLAsset(url: src)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw NSError(domain: "loop", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track"]) }
        let dur = try await asset.load(.duration)
        let (size, tf, fps) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let D = dur.seconds, F = min(fade, D / 4)
        guard D > 4 else { throw NSError(domain: "loop", code: 2, userInfo: [NSLocalizedDescriptionKey: "Clip too short"]) }
        let ts: CMTimeScale = max(dur.timescale, 600)
        func t(_ x: Double) -> CMTime { CMTime(seconds: x, preferredTimescale: ts) }

        let comp = AVMutableComposition()
        guard let a = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let b = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "loop", code: 3, userInfo: [NSLocalizedDescriptionKey: "Composition failed"]) }
        // A: body [F, D) placed at 0. B: head [0, F) placed at D-2F, underneath A while A fades out.
        try a.insertTimeRange(CMTimeRange(start: t(F), end: dur), of: track, at: .zero)
        try b.insertTimeRange(CMTimeRange(start: .zero, end: t(F)), of: track, at: t(D - 2 * F))
        a.preferredTransform = tf; b.preferredTransform = tf
        let total = t(D - F)

        let ia = AVMutableVideoCompositionLayerInstruction(assetTrack: a)
        ia.setTransform(tf, at: .zero)
        ia.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: CMTimeRange(start: t(D - 2 * F), duration: t(F)))
        let ib = AVMutableVideoCompositionLayerInstruction(assetTrack: b)
        ib.setTransform(tf, at: .zero)
        let ins = AVMutableVideoCompositionInstruction()
        _ = total
        ins.timeRange = CMTimeRange(start: .zero, duration: comp.duration)
        ins.layerInstructions = [ia, ib]
        let vc = AVMutableVideoComposition()
        vc.instructions = [ins]
        let r = CGRect(origin: .zero, size: size).applying(tf)
        vc.renderSize = CGSize(width: abs(r.width), height: abs(r.height))
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(24, min(60, fps.rounded()))))

        let preset = vc.renderSize.width > 3840 ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHEVC3840x2160
        guard let ex = AVAssetExportSession(asset: comp, presetName: preset) else {
            throw NSError(domain: "loop", code: 4, userInfo: [NSLocalizedDescriptionKey: "HEVC export unavailable"]) }
        ex.videoComposition = vc
        ex.shouldOptimizeForNetworkUse = true
        try? FileManager.default.removeItem(at: dst)
        ex.outputURL = dst
        ex.outputFileType = .mp4
        let box = ExportBox(ex)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in box.session.exportAsynchronously { c.resume() } }
        if ex.status != .completed {
            throw ex.error ?? NSError(domain: "loop", code: 5, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
    }
}

// MARK: - Media helpers

enum Media {
    /// Check the file's first bytes (not just its name) so a renamed program can't pose as a wallpaper.
    static func looksLikeMedia(_ u: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: u), let b = try? h.read(upToCount: 16), b.count >= 12 else { return false }
        try? h.close()
        let x = [UInt8](b)
        func at(_ o: Int, _ s: String) -> Bool { Array(s.utf8).enumerated().allSatisfy { o + $0.offset < x.count && x[o + $0.offset] == $0.element } }
        if at(4, "ftyp") || at(4, "moov") || at(4, "mdat") || at(4, "wide") || at(4, "free") { return true }   // MP4 / MOV / HEIC
        if x[0] == 0x1A && x[1] == 0x45 && x[2] == 0xDF && x[3] == 0xA3 { return true }                       // WebM / MKV
        if at(0, "RIFF") || at(0, "OggS") || x[0] == 0x47 || (x[0] == 0 && x[1] == 0 && x[2] == 1) { return true } // AVI/WebP, OGV, TS, MPEG
        if (x[0] == 0xFF && x[1] == 0xD8) || at(1, "PNG") || at(0, "GIF8") || at(0, "II*") || at(0, "MM\u{0}*") { return true } // JPG PNG GIF TIFF
        if at(0, "FLV") || (x[0] == 0x30 && x[1] == 0x26 && x[2] == 0xB2) { return true }                    // FLV, WMV
        return false
    }
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv", "flv", "ogv", "mpg", "mpeg", "ts"]
    static func kind(of url: URL) -> Kind? {
        let ext = url.pathExtension.lowercased()
        if videoExts.contains(ext) { return .video }
        guard let t = UTType(filenameExtension: ext) else { return nil }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return .video }
        if t.conforms(to: .image) { return .image }
        return nil
    }
    static func duration(_ path: String) async -> Double? {
        guard let d = try? await AVURLAsset(url: URL(fileURLWithPath: path)).load(.duration), d.seconds.isFinite else { return nil }
        return d.seconds
    }
    static func dims(_ path: String, _ kind: Kind) async -> (Int, Int)? {
        let url = URL(fileURLWithPath: path)
        if kind == .video {
            let a = AVURLAsset(url: url)
            guard let t = try? await a.loadTracks(withMediaType: .video).first,
                  let (size, tf) = try? await t.load(.naturalSize, .preferredTransform) else { return nil }
            let r = CGRect(origin: .zero, size: size).applying(tf)
            return (Int(abs(r.width).rounded()), Int(abs(r.height).rounded()))
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let o = p[kCGImagePropertyOrientation] as? Int ?? 1
        return o >= 5 ? (h, w) : (w, h)
    }
    static func writeJPEG(_ cg: CGImage, to url: URL, quality: Double = 0.85) -> Bool {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(d)
    }
    static func frame(_ path: String, maxSize: CGFloat, at seconds: Double = 1.5) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxSize, height: maxSize)
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity
        return try? await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }
    static func thumbnail(_ path: String, _ kind: Kind, id: String) async -> String? {
        let out = Paths.thumbs.appendingPathComponent("thumb-\(Paths.safe(id)).jpg")
        if FileManager.default.fileExists(atPath: out.path) { return out.path }
        var cg: CGImage?
        if kind == .video { cg = await frame(path, maxSize: 640) }
        else if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) {
            cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                              kCGImageSourceThumbnailMaxPixelSize: 640,
                                                              kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        }
        guard let cg, writeJPEG(cg, to: out) else { return nil }
        return out.path
    }
    /// Full-resolution still used as the macOS desktop picture behind a live video (Mission Control, other Spaces, after quit).
    static func poster(_ a: Assignment) async -> URL? {
        let out = Paths.thumbs.appendingPathComponent("poster-\(Paths.safe(a.itemID)).jpg")
        if FileManager.default.fileExists(atPath: out.path) { return out }
        guard let cg = await frame(a.path, maxSize: 3840), writeJPEG(cg, to: out, quality: 0.9) else { return nil }
        return out
    }
}

// MARK: - Screens

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
    var stableKey: String {
        if let u = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() { return CFUUIDCreateString(nil, u) as String }
        return "display-\(displayID)"
    }
    var pixelSize: String { "\(Int(frame.width * backingScaleFactor))×\(Int(frame.height * backingScaleFactor))" }
}

// MARK: - Wallpaper engine (one borderless desktop-level window + looping AVPlayer per display)

final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        title = "Lucid Desktop"
        setFrame(screen.frame, display: false)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PlayerHostView: NSView {
    let playerLayer = AVPlayerLayer()
    let dimLayer = CALayer()
    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(dimLayer)
        applyLook()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); playerLayer.frame = bounds; dimLayer.frame = bounds }
    func applyLook() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playerLayer.videoGravity = Pref.fillScreen ? .resizeAspectFill : .resizeAspect
        dimLayer.opacity = Float(min(0.8, max(0, Pref.dim)))
        CATransaction.commit()
    }
}

@MainActor final class ScreenPlayer {
    let key: String
    let assignment: Assignment
    let window: WallpaperWindow
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private(set) var host: PlayerHostView!
    var visible = true

    init(screen: NSScreen, key: String, assignment: Assignment) {
        self.key = key
        self.assignment = assignment
        window = WallpaperWindow(screen: screen)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        let item = AVPlayerItem(url: URL(fileURLWithPath: assignment.path))
        item.preferredForwardBufferDuration = 2
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.defaultRate = Float(Pref.speed)
        host = PlayerHostView(player: player)
        window.contentView = host
        window.orderFrontRegardless()
    }
    func move(to screen: NSScreen) {
        if window.frame != screen.frame { window.setFrame(screen.frame, display: true) }
    }
    func close() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
}

@MainActor final class WallpaperEngine: ObservableObject {
    @Published private(set) var state = EngineState()
    @Published private(set) var pauseReason: String?
    @Published private(set) var tick = 0
    private(set) var players: [String: ScreenPlayer] = [:]
    private var locked = false, asleep = false, onBattery = false, lowPower = false
    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        if let d = try? Data(contentsOf: Paths.state), let s = try? JSONDecoder().decode(EngineState.self, from: d) { state = s }
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        checkBattery()
        observe()
    }

    func assignment(for screen: NSScreen) -> Assignment? { state.perScreen[screen.stableKey] ?? state.all }
    func isPlaying(_ screen: NSScreen) -> Bool { (players[screen.stableKey]?.player.rate ?? 0) > 0 }
    func screenPaused(_ screen: NSScreen) -> String? {
        guard let p = players[screen.stableKey] else { return nil }
        if let r = pauseReason { return r }
        if Pref.pauseWhenCovered && !p.visible { return "Covered by a window/full-screen app" }
        return nil
    }

    private func save() { if let d = try? JSONEncoder().encode(state) { try? d.write(to: Paths.state, options: .atomic) } }

    func apply(_ a: Assignment, screenKey: String?) {
        if let k = screenKey { state.perScreen[k] = a } else { state.all = a; state.perScreen = [:] }
        state.userPaused = false
        save()
        refresh()
        let targets = NSScreen.screens.filter { screenKey == nil || $0.stableKey == screenKey }
        if a.kind == .image {
            targets.forEach { setDesktop(URL(fileURLWithPath: a.path), $0) }
        } else {
            Task { if let poster = await Media.poster(a) { targets.forEach { self.setDesktop(poster, $0) } } }
        }
    }

    func clear(screenKey: String?) {
        if let k = screenKey {
            if state.perScreen[k] != nil { state.perScreen[k] = nil }
            else if let all = state.all {
                // Screen was following "all": keep the others, blank this one by pinning others explicitly.
                for s in NSScreen.screens where s.stableKey != k { state.perScreen[s.stableKey] = state.perScreen[s.stableKey] ?? all }
                state.all = nil
            }
        } else { state.all = nil; state.perScreen = [:] }
        save(); refresh()
    }

    func forget(path: String) {
        if state.all?.path == path { state.all = nil }
        state.perScreen = state.perScreen.filter { $0.value.path != path }
        save(); refresh()
    }

    func togglePause() { state.userPaused.toggle(); save(); updatePlayback() }
    func applyLook() {
        for p in players.values { p.host.applyLook(); p.player.defaultRate = Float(Pref.speed) }
        updatePlayback()
    }

    private func setDesktop(_ url: URL, _ screen: NSScreen) {
        try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
            .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
            .allowClipping: NSNumber(value: true)])
    }

    func refresh() {
        var wanted: [String: (NSScreen, Assignment)] = [:]
        for s in NSScreen.screens {
            if let a = assignment(for: s), a.kind == .video, FileManager.default.fileExists(atPath: a.path) { wanted[s.stableKey] = (s, a) }
        }
        for (k, p) in players where wanted[k] == nil || wanted[k]!.1 != p.assignment { p.close(); players[k] = nil }
        for (k, (s, a)) in wanted {
            if let p = players[k] { p.move(to: s) }
            else {
                let p = ScreenPlayer(screen: s, key: k, assignment: a)
                players[k] = p
                let o = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: p.window, queue: .main) { [weak self, weak p] _ in
                    MainActor.assumeIsolated {
                        guard let p else { return }
                        p.visible = p.window.occlusionState.contains(.visible)
                        self?.updatePlayback()
                    }
                }
                observers.append(o)
            }
        }
        updatePlayback()
    }

    func updatePlayback() {
        var reason: String?
        if state.userPaused { reason = "Paused" }
        else if locked { reason = "Screen locked" }
        else if asleep { reason = "Display asleep" }
        else if Pref.pauseOnBattery && onBattery { reason = "On battery" }
        else if Pref.pauseLowPower && lowPower { reason = "Low Power Mode" }
        pauseReason = reason
        for p in players.values {
            let covered = Pref.pauseWhenCovered && !p.visible
            let r = Float(Pref.speed)
            if reason == nil && !covered { if p.player.rate != r { p.player.defaultRate = r; p.player.rate = r } }
            else if p.player.rate != 0 { p.player.pause() }
        }
        tick += 1
    }

    private func checkBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String? else { return }
        let b = type == "Battery Power"
        if b != onBattery { onBattery = b; updatePlayback() }
    }

    private func observe() {
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked = true; self?.updatePlayback() } })
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked = false; self?.updatePlayback() } })
        let wnc = NSWorkspace.shared.notificationCenter
        observers.append(wnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = true; self?.updatePlayback() } })
        observers.append(wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = false; self?.updatePlayback() } })
        observers.append(wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = false; self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled; self?.updatePlayback() } })
        timers.append(Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkBattery() } })
        timers.append(Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeStatus() } })
    }

    /// Diagnostic snapshot (only when `defaults write com.jedbrn.lucid writeStatus -bool YES`).
    func writeStatus() {
        guard Pref.writeStatus else { return }
        var screens: [[String: Any]] = []
        for s in NSScreen.screens {
            var row: [String: Any] = ["name": s.localizedName, "key": s.stableKey, "pixels": s.pixelSize,
                                      "assignment": assignment(for: s)?.title ?? NSNull()]
            if let p = players[s.stableKey] {
                row["windowNumber"] = p.window.windowNumber
                row["rate"] = p.player.rate
                row["gravity"] = p.host.playerLayer.videoGravity.rawValue
                row["dim"] = p.host.dimLayer.opacity
                row["time"] = p.player.currentTime().seconds
                row["visible"] = p.visible
                row["path"] = p.assignment.path
            }
            screens.append(row)
        }
        let j: [String: Any] = ["at": Date().timeIntervalSince1970, "pauseReason": pauseReason ?? NSNull(),
                                "onBattery": onBattery, "lowPower": lowPower, "locked": locked, "screens": screens]
        if let d = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: Paths.status) }
    }
}

// MARK: - Downloader

@MainActor final class Downloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: [String: Double] = [:]
    @Published var errors: [String: String] = [:]
    private var session: URLSession!
    private var jobs: [Int: (item: WallItem, done: (WallItem) -> Void)] = [:]
    private var tasksByItem: [String: URLSessionDownloadTask] = [:]

    override init() {
        super.init()
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["User-Agent": Net.ua]
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 6 * 3600
        session = URLSession(configuration: c, delegate: self, delegateQueue: .main)
    }

    func start(_ item: WallItem, done: @escaping (WallItem) -> Void) {
        guard progress[item.id] == nil, let s = item.downloadURL, let u = URL(string: s) else { return }
        errors[item.id] = nil
        let t = session.downloadTask(with: u)
        jobs[t.taskIdentifier] = (item, done)
        tasksByItem[item.id] = t
        progress[item.id] = 0
        t.resume()
    }
    func cancel(_ id: String) {
        tasksByItem[id]?.cancel()
        tasksByItem[id] = nil
        progress[id] = nil
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let tid = downloadTask.taskIdentifier
        MainActor.assumeIsolated {
            guard let job = jobs[tid] else { return }
            progress[job.item.id] = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.01
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tid = downloadTask.taskIdentifier
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        let tmp = Paths.media.appendingPathComponent(".partial-\(tid)-\(UUID().uuidString)")
        try? FileManager.default.moveItem(at: location, to: tmp)
        MainActor.assumeIsolated { finish(tid: tid, tmp: tmp, status: status) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let tid = task.taskIdentifier
        MainActor.assumeIsolated {
            guard let job = jobs.removeValue(forKey: tid) else { return }
            progress[job.item.id] = nil
            tasksByItem[job.item.id] = nil
            if (error as NSError).code != NSURLErrorCancelled { errors[job.item.id] = error.localizedDescription }
        }
    }

    private func finish(tid: Int, tmp: URL, status: Int) {
        guard let job = jobs.removeValue(forKey: tid) else { try? FileManager.default.removeItem(at: tmp); return }
        tasksByItem[job.item.id] = nil
        guard (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: tmp)
            progress[job.item.id] = nil
            errors[job.item.id] = "Download failed (HTTP \(status))."
            return
        }
        var item = job.item
        let ext = item.fileExt ?? URL(string: item.downloadURL ?? "")?.pathExtension ?? (item.kind == .video ? "mp4" : "jpg")
        let final = Paths.media.appendingPathComponent("\(Paths.safe(item.id)).\(ext.isEmpty ? "bin" : ext)")
        try? FileManager.default.removeItem(at: final)
        do { try FileManager.default.moveItem(at: tmp, to: final) } catch {
            progress[item.id] = nil; errors[item.id] = error.localizedDescription; return
        }
        Task { @MainActor in
            var final = final
            if item.kind == .video, ["webm", "ogv", "mkv"].contains(final.pathExtension.lowercased()) {
                self.progress[item.id] = 0.998
                let mp4 = final.deletingPathExtension().appendingPathExtension("mp4")
                do {
                    try await Transcoder.toHEVC(final, mp4)
                    try? FileManager.default.removeItem(at: final)
                    final = mp4; item.fileExt = "mp4"; item.codec = "hevc"
                } catch {
                    try? FileManager.default.removeItem(at: final)
                    try? FileManager.default.removeItem(at: mp4)
                    self.progress[item.id] = nil
                    self.errors[item.id] = error.localizedDescription
                    return
                }
            }
            if item.kind == .video && item.source == .live && UserDefaults.standard.object(forKey: "seamlessLoops") as? Bool ?? true {
                self.progress[item.id] = 0.999
                let looped = Paths.media.appendingPathComponent("\(Paths.safe(item.id)).loop.mp4")
                do {
                    try await LoopMaker.make(final, to: looped)
                    try? FileManager.default.removeItem(at: final)
                    try FileManager.default.moveItem(at: looped, to: final)
                    item.codec = "hevc"
                } catch {
                    try? FileManager.default.removeItem(at: looped)
                    NSLog("LoopMaker failed for \(item.id): \(error.localizedDescription) — using original")
                }
            }
            if let (w, h) = await Media.dims(final.path, item.kind) { item.width = w; item.height = h }
            item.localPath = final.path
            item.bytes = (try? FileManager.default.attributesOfItem(atPath: final.path)[.size] as? Int64) ?? item.bytes
            item.thumbPath = await Media.thumbnail(final.path, item.kind, id: item.id)
            item.addedAt = Date()
            self.progress[item.id] = nil
            job.done(item)
        }
    }
}

// MARK: - App store / view model

struct DiscoverState {
    var query = ""
    var items: [WallItem] = []
    var next: Int? = 1
    var loading = false
    var error: String?
    var rejected = 0
    var featured = true
    var generation = 0
}

enum LibFilter: String, CaseIterable { case all = "All", videos = "Videos", photos = "Photos" }

@MainActor final class Store: ObservableObject {
    static let shared = Store()
    let engine = WallpaperEngine()
    let downloader = Downloader()
    @Published var library: [WallItem] = []
    @Published var aerials: [WallItem] = []
    @Published var live: [WallItem] = []
    @Published var discover: [Source: DiscoverState] = [:]
    @Published var keysPresent: Set<KeyName> = []
    @Published var toast: String?
    @Published var favorites: [WallItem] = []
    @Published var playlists: [Playlist] = []
    @Published var activePlaylistID: String? = Pref.activePlaylist
    var downloadsTimer: Timer?
    var folderTimer: Timer?
    var adoptInFlight: Set<String> = []
    var watchSince: Date?
    var seenDownloads: Set<String> = []
    var pendingSizes: [String: Int] = [:]
    private var playlistCursor = -1
    private var history: [String] = []
    private var rotateTimer: Timer?

    init() {
        if let d = try? Data(contentsOf: Paths.library), let l = try? JSONDecoder().decode([WallItem].self, from: d) { library = l }
        aerials = Providers.aerials()
        live = LiveCatalog.load()
        if let d = try? Data(contentsOf: Paths.favorites), let f = try? JSONDecoder().decode([WallItem].self, from: d) { favorites = f }
        if let d = try? Data(contentsOf: Paths.playlists), let p = try? JSONDecoder().decode([Playlist].self, from: d) { playlists = p }
        if let a = activePlaylistID, !playlists.contains(where: { $0.id == a }) { activePlaylistID = nil; Pref.activePlaylist = nil }
        if let cur = engine.state.all?.itemID { history = [cur] }
        refreshKeys()
        for s in Source.discoverable { discover[s] = DiscoverState() }
        scheduleRotation()
        adoptStrayFiles()
        // Keep watching: files dropped into the Lucid folder while the app is open appear within seconds.
        folderTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.adoptStrayFiles() }
        }
    }

    /// Anything dropped straight into the Lucid folder (Media/ or the folder itself) isn't in library.json,
    /// so it would be invisible. On launch, pick those files up and add them to the library.
    func adoptStrayFiles() {
        let fm = FileManager.default
        let known = Set(library.compactMap(\.localPath))
        var stray: [URL] = []
        for dir in [Paths.media, Paths.support] {
            let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                                  options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            while let f = e?.nextObject() as? URL {
                if known.contains(f.path) || adoptInFlight.contains(f.path) || f.lastPathComponent.contains(".loop.") { continue }
                if Media.kind(of: f) == nil { continue }
                if let m = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   Date().timeIntervalSince(m) < 15 { continue }   // still being written
                stray.append(f)
            }
        }
        if !stray.isEmpty { stray.forEach { adoptInFlight.insert($0.path) }; importFiles(stray, move: true, quiet: false) }
    }

    func refreshKeys() { keysPresent = Set(KeyName.allCases.filter { Keychain.get($0) != nil }) }
    func saveKey(_ k: KeyName, _ v: String) {
        Keychain.set(k, v); refreshKeys()
        for s in Source.discoverable where s.needsKey == k { discover[s] = DiscoverState(); load(s, reset: true) }
    }

    private func saveLibrary() { if let d = try? JSONEncoder().encode(library) { try? d.write(to: Paths.library, options: .atomic) } }
    func libraryItem(_ id: String) -> WallItem? { library.first { $0.id == id } }
    func inLibrary(_ id: String) -> Bool { libraryItem(id)?.isLocalReady ?? false }
    func addToLibrary(_ item: WallItem) {
        library.removeAll { $0.id == item.id }
        library.insert(item, at: 0)
        saveLibrary()
    }
    func remove(_ item: WallItem) {
        guard let it = libraryItem(item.id) else { return }
        if let p = it.localPath {
            engine.forget(path: p)
            if p.hasPrefix(Paths.media.path) { try? FileManager.default.removeItem(atPath: p) }
        }
        if let t = it.thumbPath { try? FileManager.default.removeItem(atPath: t) }
        library.removeAll { $0.id == item.id }
        saveLibrary()
        flash("Removed “\(it.title)”")
    }

    // Favorites
    func isFavorite(_ id: String) -> Bool { favorites.contains { $0.id == id } }
    func toggleFavorite(_ item: WallItem) {
        if isFavorite(item.id) { favorites.removeAll { $0.id == item.id }; flash("Removed from Favorites") }
        else { var it = item; it.addedAt = it.addedAt ?? Date(); favorites.insert(it, at: 0); flash("♥ Added to Favorites") }
        if let d = try? JSONEncoder().encode(favorites) { try? d.write(to: Paths.favorites, options: .atomic) }
    }
    var currentItem: WallItem? {
        guard let id = engine.state.all?.itemID ?? engine.state.perScreen.values.first?.itemID else { return nil }
        return findItem(id)
    }
    func findItem(_ id: String) -> WallItem? {
        libraryItem(id) ?? favorites.first { $0.id == id } ?? playlists.lazy.flatMap(\.items).first { $0.id == id }
            ?? live.first { $0.id == id } ?? aerials.first { $0.id == id }
    }

    // Playlists
    private func savePlaylists() { if let d = try? JSONEncoder().encode(playlists) { try? d.write(to: Paths.playlists, options: .atomic) } }
    @discardableResult func createPlaylist(_ name: String, with item: WallItem? = nil) -> Playlist {
        var p = Playlist(name: name.trimmingCharacters(in: .whitespaces).ifEmpty("Playlist \(playlists.count + 1)"))
        if let item { p.items = [item] }
        playlists.append(p); savePlaylists(); flash("Created playlist “\(p.name)”")
        return p
    }
    func addToPlaylist(_ item: WallItem, _ pid: String) {
        guard let i = playlists.firstIndex(where: { $0.id == pid }) else { return }
        if playlists[i].items.contains(where: { $0.id == item.id }) { flash("Already in “\(playlists[i].name)”"); return }
        playlists[i].items.append(item); savePlaylists(); flash("Added to “\(playlists[i].name)”")
    }
    func removeFromPlaylist(_ id: String, _ pid: String) {
        guard let i = playlists.firstIndex(where: { $0.id == pid }) else { return }
        playlists[i].items.removeAll { $0.id == id }; savePlaylists()
    }
    func updatePlaylist(_ p: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == p.id }) else { return }
        playlists[i] = p; savePlaylists()
        if activePlaylistID == p.id { scheduleRotation() }
    }
    func deletePlaylist(_ pid: String) {
        if activePlaylistID == pid { stopPlaylist() }
        playlists.removeAll { $0.id == pid }; savePlaylists()
    }
    var activePlaylist: Playlist? { playlists.first { $0.id == activePlaylistID } }
    func playPlaylist(_ pid: String) {
        guard let p = playlists.first(where: { $0.id == pid }), !p.items.isEmpty else { flash("Add some wallpapers to this playlist first"); return }
        activePlaylistID = pid; Pref.activePlaylist = pid; playlistCursor = -1
        next(); scheduleRotation()
        flash("Playing “\(p.name)” · \(p.shuffle ? "shuffle" : "in order") · every \(Self.intervalLabel(p.minutes))")
    }
    func stopPlaylist() { activePlaylistID = nil; Pref.activePlaylist = nil; scheduleRotation() }
    static func intervalLabel(_ m: Int) -> String {
        m < 60 ? "\(m) min" : m < 1440 ? "\(m / 60) h" : "day"
    }


    private func didApply(_ id: String) {
        if let i = library.firstIndex(where: { $0.id == id }) { library[i].lastAppliedAt = Date(); saveLibrary() }
        if history.last != id { history.append(id); if history.count > 60 { history.removeFirst() } }
    }

    func flash(_ s: String) {
        toast = s
        let cur = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { if self.toast == cur { self.toast = nil } }
    }

    // Discover
    func load(_ s: Source, reset: Bool = false) {
        guard s != .aerials, var st = discover[s] else { return }
        if reset { st.items = []; st.next = 1; st.rejected = 0; st.error = nil; st.generation += 1 }
        guard let page = st.next, !st.loading || reset else { discover[s] = st; return }
        if s.needsKey.map({ !keysPresent.contains($0) }) ?? false { st.error = nil; discover[s] = st; return }
        st.loading = true; st.error = nil
        let gen = st.generation, q = st.query, featured = st.featured
        discover[s] = st
        Task {
            do {
                let r = try await Providers.fetch(s, query: q, page: s == .wikimedia ? (page == 1 ? 0 : page) : page, featured: featured)
                guard var cur = discover[s], cur.generation == gen else { return }
                let have = Set(cur.items.map(\.id))
                cur.items += r.items.filter { !have.contains($0.id) }
                cur.next = r.next; cur.rejected += r.rejected; cur.loading = false
                discover[s] = cur
                // Keep fetching if a page was entirely filtered out by the 4K bar.
                if r.items.isEmpty, r.next != nil, cur.items.count < 12 { load(s) }
            } catch {
                guard var cur = discover[s], cur.generation == gen else { return }
                cur.loading = false; cur.error = error.localizedDescription
                discover[s] = cur
            }
        }
    }
    func search(_ s: Source, _ q: String) {
        discover[s]?.query = q
        load(s, reset: true)
    }

    // Applying
    func setWallpaper(_ item: WallItem, screenKey: String? = nil) {
        if let lib = libraryItem(item.id), lib.isLocalReady, let p = lib.localPath {
            engine.apply(Assignment(itemID: lib.id, title: lib.title, path: p, kind: lib.kind), screenKey: screenKey)
            didApply(lib.id)
            flash("Wallpaper set: \(lib.title)")
            return
        }
        if item.source == .aerials, let p = item.localPath, FileManager.default.fileExists(atPath: p) {
            Task {
                var it = item
                it.thumbPath = await Media.thumbnail(p, .video, id: it.id)
                it.addedAt = Date()
                addToLibrary(it)
                engine.apply(Assignment(itemID: it.id, title: it.title, path: p, kind: .video), screenKey: screenKey)
                didApply(it.id)
                flash("Wallpaper set: \(it.title)")
            }
            return
        }
        flash("Downloading “\(item.title)” in \(item.resLabel)…")
        downloader.start(item) { [weak self] done in
            guard let self else { return }
            self.addToLibrary(done)
            if let p = done.localPath {
                self.engine.apply(Assignment(itemID: done.id, title: done.title, path: p, kind: done.kind), screenKey: screenKey)
                self.didApply(done.id)
                self.flash("Wallpaper set: \(done.title)")
            }
        }
    }
    func download(_ item: WallItem) {
        if item.source == .aerials, item.localPath != nil { setLibraryOnly(item); return }
        downloader.start(item) { [weak self] done in self?.addToLibrary(done); self?.flash("Saved to library: \(done.title)") }
    }
    private func setLibraryOnly(_ item: WallItem) {
        Task {
            var it = item
            if let p = it.localPath { it.thumbPath = await Media.thumbnail(p, .video, id: it.id) }
            it.addedAt = Date()
            addToLibrary(it); flash("Added to library: \(it.title)")
        }
    }

    enum ImportResult { case added(Bool), duplicate, unsupported, failed(String) }

    /// Drag & drop, Dock and Downloads-folder imports all land here. Files are COPIED
    /// into the app's Media folder so deleting ~/Downloads never breaks a wallpaper. Formats AVFoundation
    /// can't play (WebM, MKV, AVI…) are converted to HEVC.
    func importFiles(_ urls: [URL], move: Bool = false, site: String? = nil, page: String? = nil, quiet: Bool = false) {
        let local = urls.filter(\.isFileURL)
        guard !local.isEmpty else { return }
        Task {
            var files: [URL] = []
            for u in local {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                    let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    while let f = e?.nextObject() as? URL { if Media.kind(of: f) != nil { files.append(f) } }
                } else { files.append(u) }
            }
            if files.count > 1 || !quiet { flash(files.count > 1 ? "Importing \(files.count) files…" : "Importing \(files.first?.lastPathComponent ?? "")…") }
            var added = 0, low = 0, dup = 0, unsup = 0
            var failed: [String] = []
            for u in files {
                switch await importOne(u, move: move, site: site, page: page) {
                case .added(let is4K): added += 1; if !is4K { low += 1 }
                case .duplicate: dup += 1
                case .unsupported: unsup += 1
                case .failed(let m): failed.append("\(u.lastPathComponent): \(m)")
                }
            }
            var msg = added == 1 ? "Added to your library" : "Imported \(added) wallpapers"
            if added == 0 { msg = dup > 0 ? "Already in your library" : "Nothing imported" }
            if low > 0 { msg += " · \(low) below 4K (flagged)" }
            if unsup > 0 { msg += " · \(unsup) not a video/photo" }
            if !failed.isEmpty { msg += " · failed: " + failed.prefix(2).joined(separator: "; ") }
            flash(msg)
        }
    }

    func importOne(_ u: URL, move: Bool, site: String?, page: String?) async -> ImportResult {
        guard let k = Media.kind(of: u), Media.looksLikeMedia(u) else { return .unsupported }
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: u.path)[.size] as? Int64) ?? 0
        let base = u.deletingPathExtension().lastPathComponent
        let id = "local:" + Paths.safe("\(base)-\(size)")
        if inLibrary(id) && (libraryItem(id)?.isLocalReady ?? false) { if move { try? fm.removeItem(at: u) }; return .duplicate }
        let ext = u.pathExtension.lowercased()
        var needsTx = false
        if k == .video {
            let playable = (try? await AVURLAsset(url: u).load(.isPlayable)) ?? false
            needsTx = !playable || ["webm", "mkv", "avi", "wmv", "flv", "ogv"].contains(ext)
        }
        var dest = Paths.media.appendingPathComponent(Paths.safe(base) + "-" + String(size, radix: 36) + "." + (needsTx ? "mp4" : ext))
        do {
            if u.standardizedFileURL.path.hasPrefix(Paths.media.standardizedFileURL.path) { dest = u }
            else if needsTx {
                try await Transcoder.toHEVC(u, dest)
                if move { try? fm.removeItem(at: u) }
            } else {
                try? fm.removeItem(at: dest)
                if move { try fm.moveItem(at: u, to: dest) } else { try fm.copyItem(at: u, to: dest) }
            }
        } catch { return .failed(error.localizedDescription) }
        let dims = await Media.dims(dest.path, k) ?? (0, 0)
        var it = WallItem(id: id, source: .local, kind: k, title: Importer.niceTitle(base),
                          width: dims.0, height: dims.1,
                          license: site.map { "Downloaded from \($0) for personal use. Rights stay with the original artist/owner." } ?? "Your file",
                          fileExt: dest.pathExtension, localPath: dest.path)
        it.author = site
        it.pageURL = page
        it.thumbPath = await Media.thumbnail(dest.path, k, id: id)
        it.bytes = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int64)
        it.duration = k == .video ? await Media.duration(dest.path) : nil
        it.addedAt = Date()
        it.tags = site.map { [$0.components(separatedBy: ".").first ?? $0] }
        addToLibrary(it)
        return .added(it.is4K)
    }

    // Watch ~/Downloads: new ≥4K videos/photos are copied into the library automatically (opt-in).
    func startDownloadsWatcher() {
        downloadsTimer?.invalidate(); downloadsTimer = nil
        guard Pref.watchDownloads else { return }
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        if watchSince == nil { watchSince = Date() }
        downloadsTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanDownloads(dir) }
        }
    }
    private func scanDownloads(_ dir: URL) {
        guard let since = watchSince, let items = try? FileManager.default.contentsOfDirectory(at: dir,
              includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return }
        for f in items where Media.kind(of: f) != nil && !seenDownloads.contains(f.path) {
            let v = try? f.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            guard let c = v?.creationDate, c > since, let sz = v?.fileSize, sz > 0 else { continue }
            if pendingSizes[f.path] != sz { pendingSizes[f.path] = sz; continue }   // wait until the size stops changing
            seenDownloads.insert(f.path); pendingSizes[f.path] = nil
            Task {
                guard let k = Media.kind(of: f), let d = await Media.dims(f.path, k) else { return }
                if max(d.0, d.1) >= 3840 && min(d.0, d.1) >= 2160 { importFiles([f], quiet: true) }
            }
        }
    }

    // Rotation / next
    func next() {
        let cur = engine.state.all?.itemID
        if let p = activePlaylist, !p.items.isEmpty {
            let idx: Int
            if p.shuffle {
                let others = p.items.indices.filter { p.items[$0].id != cur }
                idx = others.randomElement() ?? 0
            } else { idx = (playlistCursor + 1) % p.items.count }
            playlistCursor = idx
            let it = p.items[idx]
            setWallpaper(libraryItem(it.id) ?? it)
            return
        }
        let pool = library.filter { $0.isLocalReady && $0.id != cur }
        guard let pick = pool.randomElement() else { flash("Add more wallpapers to your library first"); return }
        setWallpaper(pick)
    }
    func previous() {
        guard history.count >= 2 else { flash("No previous wallpaper yet"); return }
        history.removeLast()
        let id = history.removeLast()
        guard let it = findItem(id) else { flash("Previous wallpaper is no longer available"); return }
        setWallpaper(it)
    }
    func scheduleRotation() {
        rotateTimer?.invalidate(); rotateTimer = nil
        let m = activePlaylist?.minutes ?? Pref.rotateMinutes
        guard m > 0 else { return }
        rotateTimer = Timer.scheduledTimer(withTimeInterval: Double(m) * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() } }
    }

    var libraryBytes: Int64 { library.filter { $0.localPath?.hasPrefix(Paths.media.path) ?? false }.compactMap(\.bytes).reduce(0, +) }

    // Self-test (headless): `open -a "Lucid" --args -selftest YES`
    func runSelfTest() async -> [String: Any] {
        var r: [String: Any] = [:]
        let a = aerials
        r["aerials_count"] = a.count
        r["live_count"] = live.count
        r["live_all_4k"] = live.allSatisfy(\.is4K)
        r["live_by_collection"] = Dictionary(grouping: live, by: { $0.author ?? "?" }).mapValues(\.count)
        r["live_unique_ids"] = Set(live.map(\.id)).count == live.count
        r["live_codecs_ok"] = live.allSatisfy { ["h264", "hevc"].contains($0.codec ?? "") || ($0.codec == "webm" && Transcoder.ffmpeg != nil) }
        r["live_all_have_credit_and_terms"] = live.allSatisfy { ($0.creditFull ?? "").count > 2 && $0.termsURL != nil && $0.pageURL != nil }
        r["aerials_all_4k_declared"] = a.allSatisfy(\.is4K)
        r["aerials_cached_on_mac"] = a.filter { $0.localPath != nil }.count
        if let c = a.first(where: { $0.localPath != nil }), let p = c.localPath, let d = await Media.dims(p, .video) {
            r["aerials_probe"] = ["title": c.title, "width": d.0, "height": d.1]
        }
        do {
            let w = try await Providers.wikimedia("night city", offset: 0, featured: false)
            r["wikimedia_count"] = w.items.count
            r["wikimedia_rejected_below_4k"] = w.rejected
            r["wikimedia_all_4k"] = w.items.allSatisfy(\.is4K)
            r["wikimedia_sample"] = w.items.prefix(3).map { "\($0.title) \($0.width)x\($0.height) \($0.license ?? "")" }
            let f = try await Providers.wikimedia("", offset: 0, featured: true)
            r["wikimedia_featured_count"] = f.items.count
        } catch { r["wikimedia_error"] = error.localizedDescription }
        do {
            let n = try await Providers.nasa("nebula", page: 1)
            r["nasa_count"] = n.items.count
            r["nasa_rejected_below_4k"] = n.rejected
            r["nasa_all_4k"] = n.items.allSatisfy(\.is4K)
            r["nasa_sample"] = n.items.prefix(3).map { "\($0.title) \($0.width)x\($0.height)" }
        } catch { r["nasa_error"] = error.localizedDescription }
        for (k, s) in [(KeyName.pixabay, Source.pixabayVideo)] {
            guard keysPresent.contains(k) else { r["\(s.rawValue)"] = "no key"; continue }
            do { let p = try await Providers.fetch(s, query: "city night", page: 1, featured: false)
                r["\(s.rawValue)"] = ["count": p.items.count, "rejected": p.rejected, "all_4k": p.items.allSatisfy(\.is4K)]
            } catch { r["\(s.rawValue)"] = "error: \(error.localizedDescription)" }
        }
        r["favorites"] = favorites.count
        r["playlists"] = playlists.count
        r["screens"] = NSScreen.screens.map { "\($0.localizedName) \($0.pixelSize)" }
        return r
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ app: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { Store.shared.importFiles(urls); NSApp.activate(ignoringOtherApps: true) }
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        MainActor.assumeIsolated {
            let store = Store.shared
            store.engine.refresh()
            store.startDownloadsWatcher()
            let args = UserDefaults.standard
            if args.bool(forKey: "selftest") {
                Task { @MainActor in
                    let r = await store.runSelfTest()
                    if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: Paths.selftest) }
                    NSApp.terminate(nil)
                }
            }
            if let p = args.string(forKey: "applyPath"), FileManager.default.fileExists(atPath: p) {
                let u = URL(fileURLWithPath: p)
                Task { @MainActor in
                    store.importFiles([u])
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let it = store.libraryItem("local:\(Paths.safe(p))") { store.setWallpaper(it) }
                }
            }
            if let id = args.string(forKey: "applyAerial"), let it = store.aerials.first(where: { $0.id == "aerials:\(id)" || $0.title == id }) {
                store.setWallpaper(it)
            }
            if let src = args.string(forKey: "testLoop") {
                Task {
                    let dst = URL(fileURLWithPath: src + ".loop.mp4")
                    do { try await LoopMaker.make(URL(fileURLWithPath: src), to: dst); print("LOOP_OK \(dst.path)") }
                    catch { print("LOOP_FAIL \(error.localizedDescription)") }
                    exit(0)
                }
                return
            }
            if let t = args.string(forKey: "testLive"), let it = store.live.first(where: { $0.id.contains(t) }) ?? store.live.first {
                store.setWallpaper(it)
            }
            if let q = args.string(forKey: "testDownloadWikimedia") {
                Task { @MainActor in
                    if let r = try? await Providers.wikimedia(q, offset: 0, featured: true), let first = r.items.first {
                        store.setWallpaper(first)
                    }
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
}

@main
struct LucidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        Window("Lucid", id: "main") {
            ContentView()
                .environmentObject(store).environmentObject(store.engine).environmentObject(store.downloader)
                .frame(minWidth: 1020, minHeight: 660)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1240, height: 800)
        Settings {
            SettingsView().environmentObject(store).environmentObject(store.engine)
                .frame(width: 560).padding(20).preferredColorScheme(.dark)
        }
        MenuBarExtra("Lucid", systemImage: "sparkles.tv") {
            MenuContent().environmentObject(store).environmentObject(store.engine)
        }
    }
}


// MARK: - Import helpers

enum Importer {
    /// "kratos-atreus-winter-hunt.3840x2160" -> "Kratos Atreus Winter Hunt"
    static func niceTitle(_ base: String) -> String {
        var t = base
        t = t.replacingOccurrences(of: #"[._ -]?(\d{3,4}x\d{3,4}|4k|uhd|2160p|hd|1080p)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"[-_.]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if t.isEmpty { t = base }
        return t.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

// MARK: - Views

enum Nav: Hashable { case discover(Source), library(LibFilter), favorites, recents, playlist(String), displays, settings }

let accent = Color(red: 0.0, green: 0.94, blue: 1.0)
let accent2 = Color(red: 1.0, green: 0.17, blue: 0.84)

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: WallpaperEngine
    @State private var nav: Nav? = .discover(.aerials)
    @State private var newPlaylist = false
    @State private var newName = ""
    @State private var droppingAny = false

    var body: some View {
        NavigationSplitView {
            List(selection: $nav) {
                Section("Discover · 4K only") {
                    ForEach(Source.discoverable) { s in
                        Label(s.label, systemImage: s.icon).tag(Nav.discover(s))
                    }
                }
                Section("My Library") {
                    Label("Downloaded", systemImage: "square.grid.2x2").badge(store.library.filter(\.isLocalReady).count).tag(Nav.library(.all))
                    Label("Favorites", systemImage: "heart").badge(store.favorites.count).tag(Nav.favorites)
                    Label("Recently Used", systemImage: "clock.arrow.circlepath").tag(Nav.recents)
                }
                Section {
                    ForEach(store.playlists) { pl in
                        Label(pl.name, systemImage: store.activePlaylistID == pl.id ? "play.circle.fill" : "music.note.list")
                            .badge(pl.items.count).tag(Nav.playlist(pl.id))
                    }
                    Button { newName = ""; newPlaylist = true } label: { Label("New Playlist…", systemImage: "plus") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                } header: { Text("Playlists") }
                Section("Playback") {
                    Label("Displays", systemImage: "display.2").tag(Nav.displays)
                    Label("Settings", systemImage: "gearshape").tag(Nav.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .alert("New Playlist", isPresented: $newPlaylist) {
                TextField("Name (e.g. Cozy Rain, Space Night)", text: $newName)
                Button("Create") { let p = store.createPlaylist(newName); nav = .playlist(p.id) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Group wallpapers and let them rotate on a timer.") }
            .safeAreaInset(edge: .bottom) { NowPlayingBar().padding(10) }
        } detail: {
            Group {
                switch nav ?? .discover(.aerials) {
                case .discover(let s): s == .aerials ? AnyView(AerialsView()) : s == .live ? AnyView(LiveView()) : AnyView(DiscoverView(source: s).id(s))
                case .library: AnyView(LibraryView(mode: .downloaded))
                case .favorites: AnyView(LibraryView(mode: .favorites))
                case .recents: AnyView(LibraryView(mode: .recents))
                case .playlist(let id): AnyView(PlaylistView(id: id).id(id))
                case .displays: AnyView(DisplaysView())
                case .settings: AnyView(ScrollView { SettingsView().padding(24).frame(maxWidth: 640, alignment: .leading) })
                }
            }
            .overlay {
                if droppingAny {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.55))
                        RoundedRectangle(cornerRadius: 18).stroke(accent, style: StrokeStyle(lineWidth: 3, dash: [12]))
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 46)).foregroundStyle(accent)
                            Text("Drop to add to your library").font(.title2.bold())
                            Text("Videos (MP4, MOV, WebM, MKV…) and photos · or drop a whole folder").foregroundStyle(.secondary)
                        }
                    }.padding(10).allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in store.importFiles(urls); return !urls.isEmpty } isTargeted: { droppingAny = $0 }
            .overlay(alignment: .bottom) {
                if let t = store.toast {
                    Text(t).font(.callout.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(accent.opacity(0.5)))
                        .padding(.bottom, 18).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: store.toast)
        }
    }
}

struct NowPlayingBar: View {
    @EnvironmentObject var engine: WallpaperEngine
    @EnvironmentObject var store: Store
    var body: some View {
        let title = engine.state.all?.title ?? engine.state.perScreen.values.first?.title
        VStack(alignment: .leading, spacing: 6) {
            Text("NOW ON DESKTOP").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(title ?? "Nothing set yet").font(.callout.weight(.semibold)).lineLimit(1)
            if let p = store.activePlaylist {
                Text("▶︎ \(p.name) · every \(Store.intervalLabel(p.minutes))").font(.caption2).foregroundStyle(accent).lineLimit(1)
            }
            HStack(spacing: 8) {
                Button { store.previous() } label: { Image(systemName: "backward.fill") }.help("Previous wallpaper")
                Button { engine.togglePause() } label: { Image(systemName: engine.state.userPaused ? "play.fill" : "pause.fill") }
                    .help(engine.state.userPaused ? "Resume" : "Pause")
                Button { store.next() } label: { Image(systemName: "forward.fill") }
                    .help(store.activePlaylist.map { "Next in “\($0.name)”" } ?? "Random wallpaper from library")
                if let c = store.currentItem {
                    Button { store.toggleFavorite(c) } label: { Image(systemName: store.isFavorite(c.id) ? "heart.fill" : "heart") }
                        .foregroundStyle(store.isFavorite(c.id) ? accent2 : .primary).help("Favorite")
                }
                Spacer()
                if let r = engine.pauseReason { Text(r).font(.caption2).foregroundStyle(.orange).lineLimit(1) }
            }
            .buttonStyle(.borderless)
            .disabled(title == nil)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}

// Image loading with UA header + memory cache
final class ImageCache { static let shared: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 600; return c }() }

struct RemoteImage: View {
    let url: String?
    var localPath: String? = nil
    @State private var img: NSImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            Rectangle().fill(LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            if let img { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) }
            else if failed { Image(systemName: "photo").foregroundStyle(.tertiary) }
            else { ProgressView().controlSize(.small) }
        }
        .task(id: (localPath ?? "") + (url ?? "")) { await load() }
    }
    private func load() async {
        let key = (localPath ?? url ?? "") as NSString
        if let c = ImageCache.shared.object(forKey: key) { img = c; return }
        if let p = localPath, FileManager.default.fileExists(atPath: p) {
            if let i = NSImage(contentsOfFile: p) { ImageCache.shared.setObject(i, forKey: key); img = i; return }
        }
        guard let s = url, let u = URL(string: s) else { failed = true; return }
        do {
            let (d, _) = try await Net.session.data(from: u)
            if let i = NSImage(data: d) { ImageCache.shared.setObject(i, forKey: key); img = i } else { failed = true }
        } catch { failed = true }
    }
}

struct Badge: View {
    let text: String; var color: Color = accent
    var body: some View {
        Text(text).font(.caption2.weight(.heavy)).padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.65))).overlay(Capsule().stroke(color.opacity(0.8), lineWidth: 1))
            .foregroundStyle(color)
    }
}

struct Card: View {
    let item: WallItem
    @EnvironmentObject var store: Store
    @EnvironmentObject var dl: Downloader
    @EnvironmentObject var engine: WallpaperEngine
    @State private var hover = false
    var body: some View {
        let current = engine.state.all?.itemID == item.id || engine.state.perScreen.values.contains { $0.itemID == item.id }
        VStack(alignment: .leading, spacing: 6) {
            Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                .overlay(RemoteImage(url: item.thumbURL, localPath: item.thumbPath))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(current ? accent : (hover ? accent.opacity(0.5) : Color.white.opacity(0.08)), lineWidth: current ? 2 : 1))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        Badge(text: item.resLabel, color: item.is4K ? accent : .orange)
                        if item.kind == .video { Badge(text: "LIVE", color: accent2) }
                    }.padding(7)
                }
                .overlay(alignment: .topTrailing) {
                    if current { Image(systemName: "checkmark.seal.fill").foregroundStyle(accent).padding(7) }
                    else if store.isFavorite(item.id) && !hover { Image(systemName: "heart.fill").foregroundStyle(accent2).padding(7) }
                    else if store.inLibrary(item.id) || (item.source == .aerials && item.localPath != nil) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.white.opacity(0.85)).padding(7).help("On this Mac")
                    }
                }
                .overlay(alignment: .bottom) {
                    if let p = dl.progress[item.id] {
                        ProgressView(value: p).tint(accent).padding(8).background(.black.opacity(0.4))
                    } else if hover {
                        HStack(spacing: 6) {
                            Button { store.toggleFavorite(item) } label: {
                                Image(systemName: store.isFavorite(item.id) ? "heart.fill" : "heart")
                                    .foregroundStyle(store.isFavorite(item.id) ? accent2 : .white)
                            }.help("Favorite")
                            Spacer()
                            Button { store.setWallpaper(item) } label: {
                                Label(current ? "On Desktop" : "Apply", systemImage: current ? "checkmark" : "sparkles.tv").font(.caption.weight(.bold))
                            }.help("Set as wallpaper on all displays")
                        }
                        .buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 7)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .scaleEffect(hover ? 1.015 : 1).animation(.easeOut(duration: 0.15), value: hover)
            Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
            Text([item.author, item.category].compactMap { $0 }.joined(separator: " · ").ifEmpty(item.source.label))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

extension String { func ifEmpty(_ s: String) -> String { isEmpty ? s : self } }

struct ItemMenu: View {
    let item: WallItem
    var playlistID: String? = nil
    @EnvironmentObject var store: Store
    var body: some View {
        Button("Set as Wallpaper (All Displays)") { store.setWallpaper(item) }
        if NSScreen.screens.count > 1 {
            ForEach(NSScreen.screens, id: \.stableKey) { s in
                Button("Set on \(s.localizedName)") { store.setWallpaper(item, screenKey: s.stableKey) }
            }
        }
        Divider()
        Button(store.isFavorite(item.id) ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(item) }
        Menu("Add to Playlist") {
            ForEach(store.playlists) { pl in Button(pl.name) { store.addToPlaylist(item, pl.id) } }
            if !store.playlists.isEmpty { Divider() }
            Button("New Playlist with This") { store.createPlaylist("", with: item) }
        }
        if let pid = playlistID { Button("Remove from This Playlist") { store.removeFromPlaylist(item.id, pid) } }
        Divider()
        if let lib = store.libraryItem(item.id) {
            if let p = lib.localPath { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) } }
            Button("Remove from Library", role: .destructive) { store.remove(lib) }
        } else {
            Button("Download to Library") { store.download(item) }
        }
        if let p = item.pageURL, let u = URL(string: p) { Button("Open Source Page") { NSWorkspace.shared.open(u) } }
    }
}

struct Grid: View {
    let items: [WallItem]
    @Binding var selected: WallItem?
    var playlistID: String? = nil
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 420), spacing: 18)], spacing: 20) {
            ForEach(items) { item in
                Card(item: item)
                    .onTapGesture { selected = item }
                    .contextMenu { ItemMenu(item: item, playlistID: playlistID) }
            }
        }
    }
}

struct Header: View {
    let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct Chips: View {
    let options: [String]; let selected: String; let onPick: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { o in
                    Button(o) { onPick(o) }
                        .buttonStyle(.plain).font(.callout.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(o == selected ? accent.opacity(0.22) : Color.white.opacity(0.06)))
                        .overlay(Capsule().stroke(o == selected ? accent : Color.clear))
                }
            }
        }
    }
}

struct AerialsView: View {
    @EnvironmentObject var store: Store
    @State private var cat = "All"
    @State private var q = ""
    @State private var selected: WallItem?
    var body: some View {
        let cats = ["All"] + Array(Set(store.aerials.compactMap(\.category))).sorted() + ["On this Mac"]
        let items = store.aerials.filter { a in
            (cat == "All" || (cat == "On this Mac" ? a.localPath != nil : a.category == cat)) &&
            (q.isEmpty || a.title.localizedCaseInsensitiveContains(q) || (a.author ?? "").localizedCaseInsensitiveContains(q))
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Header(title: "Apple Aerials", subtitle: Source.aerials.blurb + " Each film is ~300–600 MB; ones already on this Mac apply instantly.")
                HStack {
                    TextField("Search aerials (e.g. Dubai, ocean, night)", text: $q).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    Text("\(items.count) of \(store.aerials.count)").font(.caption).foregroundStyle(.secondary)
                }
                Chips(options: cats, selected: cat) { cat = $0 }
                if store.aerials.isEmpty {
                    Text("Apple's Aerials catalog wasn't found on this Mac. Open System Settings → Wallpaper once so macOS downloads it.")
                        .foregroundStyle(.secondary)
                }
                Grid(items: items, selected: $selected)
            }.padding(24)
        }
        .sheet(item: $selected) { DetailView(item: $0) }
    }
}

struct LiveView: View {
    @EnvironmentObject var store: Store
    @State private var col = "All"
    @State private var tag = "All"
    @State private var q = ""
    @State private var selected: WallItem?
    var body: some View {
        let cols = ["All"] + Array(Set(store.live.compactMap(\.author))).sorted()
        let tags = ["All"] + Array(Set(store.live.compactMap(\.category))).sorted()
        let items = store.live.filter { a in
            (col == "All" || a.author == col) && (tag == "All" || a.category == tag) &&
            (q.isEmpty || a.title.localizedCaseInsensitiveContains(q))
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Header(title: "Live 4K", subtitle: Source.live.blurb)
                HStack {
                    TextField("Search (e.g. nebula, galaxy, Earth, zoom)", text: $q).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    Text("\(items.count) of \(store.live.count) clips").font(.caption).foregroundStyle(.secondary)
                }
                Chips(options: cols, selected: col) { col = $0 }
                Chips(options: tags, selected: tag) { tag = $0 }
                if store.live.isEmpty {
                    Text("The live catalog is empty. Run tools/build_catalog.py to rebuild it.").foregroundStyle(.secondary)
                }
                Grid(items: items, selected: $selected)
            }.padding(24)
        }
        .sheet(item: $selected) { DetailView(item: $0) }
    }
}

struct DiscoverView: View {
    let source: Source
    @EnvironmentObject var store: Store
    @State private var q = ""
    @State private var selected: WallItem?
    var body: some View {
        let st = store.discover[source] ?? DiscoverState()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Header(title: source.label, subtitle: source.blurb)
                if let k = source.needsKey, !store.keysPresent.contains(k) {
                    KeyPrompt(key: k)
                } else {
                    HStack(spacing: 10) {
                        TextField("Search \(source.label)…", text: $q).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
                            .onSubmit { store.search(source, q) }
                        Button("Search") { store.search(source, q) }
                        if source == .wikimedia {
                            Toggle("Featured pictures only", isOn: Binding(get: { st.featured }, set: { store.discover[source]?.featured = $0; store.load(source, reset: true) }))
                                .toggleStyle(.checkbox)
                        }
                        Spacer()
                        if st.rejected > 0 { Text("\(st.rejected) hidden: below 4K").font(.caption).foregroundStyle(.orange) }
                    }
                    Chips(options: source.quickQueries, selected: st.query) { o in q = o; store.search(source, o) }
                    if let e = st.error {
                        Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Button("Retry") { store.load(source) }
                    }
                    if !st.loading && st.items.isEmpty && st.error == nil && st.next == nil {
                        Text("No 4K results for “\(st.query)”. Try a broader word.").foregroundStyle(.secondary)
                    }
                    Grid(items: st.items, selected: $selected)
                    HStack {
                        Spacer()
                        if st.loading { ProgressView() }
                        else if st.next != nil && !st.items.isEmpty { Button("Load more") { store.load(source) }.onAppear { store.load(source) } }
                        Spacer()
                    }.padding(.vertical, 8)
                }
            }.padding(24)
        }
        .onAppear {
            q = st.query
            if st.items.isEmpty && !st.loading { store.load(source, reset: true) }
        }
        .sheet(item: $selected) { DetailView(item: $0) }
    }
}

struct KeyPrompt: View {
    let key: KeyName
    @EnvironmentObject var store: Store
    @State private var value = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("One-time setup: free \(key.label) API key", systemImage: "key.fill").font(.headline)
            Text("\(key.label) requires a free personal API key. Sign up, copy your key, and paste it here. It's stored in your macOS Keychain and only sent to \(key.label).")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                SecureField("\(key.label) API key", text: $value).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
                Button("Save") { store.saveKey(key, value); value = "" }.disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                Link("Get a free key ↗", destination: key.signupURL)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.35)))
    }
}

final class PreviewPlayer: ObservableObject {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    func start(_ url: URL) {
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
    }
    func stop() { player.pause(); looper?.disableLooping(); looper = nil; player.removeAllItems() }
}

struct DetailView: View {
    let item: WallItem
    @EnvironmentObject var store: Store
    @EnvironmentObject var dl: Downloader
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = PreviewPlayer()
    @State private var started = false

    var body: some View {
        let lib = store.libraryItem(item.id)
        let it = lib ?? item
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                if it.kind == .video && started {
                    VideoPlayer(player: preview.player).disabled(true)
                } else {
                    RemoteImage(url: it.previewURL.flatMap { it.kind == .image ? $0 : nil } ?? it.thumbURL, localPath: it.kind == .image ? it.localPath : it.thumbPath)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.3)))

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(it.title).font(.title2.bold()).lineLimit(2)
                    Text([it.author, it.category, it.source.label].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                    if let t = it.tags, !t.isEmpty { Text(t.map { "#\($0)" }.joined(separator: " ")).font(.caption).foregroundStyle(accent.opacity(0.8)) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Badge(text: it.resLabel, color: it.is4K ? accent : .orange)
                        if it.kind == .video { Badge(text: "LIVE", color: accent2) }
                    }
                    Text(mediaDescription(it))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if !it.is4K { Text("Below 4K").font(.caption.bold()).foregroundStyle(.orange) }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield").foregroundStyle(.secondary)
                Text("License: \(it.license ?? "—")").font(.callout).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if let u = it.termsURL.flatMap(URL.init(string:)) ?? it.source.licenseURL { Link("terms ↗", destination: u).font(.callout) }
            }
            if let p = dl.progress[item.id] {
                HStack {
                    ProgressView(value: p).tint(accent)
                    Text("\(Int(p * 100))%").font(.caption.monospacedDigit())
                    Button("Cancel") { dl.cancel(item.id) }.buttonStyle(.borderless)
                }
            }
            if let e = dl.errors[item.id] { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            HStack(spacing: 10) {
                Button { store.setWallpaper(it) } label: { Label("Set as Wallpaper", systemImage: "sparkles.tv") }
                    .buttonStyle(.borderedProminent).tint(accent.opacity(0.85)).keyboardShortcut(.defaultAction)
                    .disabled(dl.progress[item.id] != nil)
                if NSScreen.screens.count > 1 {
                    Menu("Set on Display") {
                        ForEach(NSScreen.screens, id: \.stableKey) { s in
                            Button(s.localizedName) { store.setWallpaper(it, screenKey: s.stableKey) }
                        }
                    }.fixedSize()
                }
                if lib == nil && !(it.source == .aerials && it.localPath != nil) {
                    Button("Download") { store.download(it) }.disabled(dl.progress[item.id] != nil)
                }
                Button { store.toggleFavorite(it) } label: {
                    Image(systemName: store.isFavorite(it.id) ? "heart.fill" : "heart").foregroundStyle(store.isFavorite(it.id) ? accent2 : .primary)
                }.help("Favorite")
                Menu {
                    ForEach(store.playlists) { pl in Button(pl.name) { store.addToPlaylist(it, pl.id) } }
                    if !store.playlists.isEmpty { Divider() }
                    Button("New Playlist with This") { store.createPlaylist("", with: it) }
                } label: { Image(systemName: "text.badge.plus") }.fixedSize().help("Add to playlist")
                if let p = it.pageURL, let u = URL(string: p) { Button("Source ↗") { NSWorkspace.shared.open(u) } }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 820)
        .onAppear {
            guard it.kind == .video else { return }
            let src: URL? = it.localPath.map { URL(fileURLWithPath: $0) } ?? it.previewURL.flatMap(URL.init(string:))
            if let src { preview.start(src); started = true }
        }
        .onDisappear { preview.stop() }
    }
}

private func mediaDescription(_ it: WallItem) -> String {
    var parts = ["\(it.width)×\(it.height)"]
    if let codec = it.codec { parts.append(codec.uppercased()) }
    if let duration = it.duration { parts.append("\(Int(duration))s video") }
    if let bytes = it.bytes { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
    return parts.joined(separator: " · ")
}

enum LibMode { case downloaded, favorites, recents }
enum LibSort: String, CaseIterable { case added = "Recently Added", used = "Recently Used", name = "Name", size = "Largest" }

struct LibraryView: View {
    let mode: LibMode
    @EnvironmentObject var store: Store
    @State private var selected: WallItem?
    @State private var dropping = false
    @State private var kind = "All"
    @State private var q = ""
    @State private var sort: LibSort = .added

    private var base: [WallItem] {
        switch mode {
        case .downloaded: return store.library.filter(\.isLocalReady)
        case .favorites: return store.favorites.map { store.libraryItem($0.id) ?? $0 }
        case .recents: return Array(store.library.filter { $0.lastAppliedAt != nil && $0.isLocalReady }
                .sorted { ($0.lastAppliedAt ?? .distantPast) > ($1.lastAppliedAt ?? .distantPast) }.prefix(40))
        }
    }
    private var title: String { mode == .downloaded ? "Downloaded" : mode == .favorites ? "Favorites" : "Recently Used" }

    private func filtered() -> [WallItem] {
        var items = base.filter { it in
            let kindOK = kind == "All" || (kind == "Videos" ? it.kind == .video : kind == "Photos" ? it.kind == .image : it.source.label == kind)
            let qOK = q.isEmpty || it.title.localizedCaseInsensitiveContains(q) || (it.author ?? "").localizedCaseInsensitiveContains(q)
                || (it.tags ?? []).contains { $0.localizedCaseInsensitiveContains(q) }
            return kindOK && qOK
        }
        if mode != .recents {
            switch sort {
            case .added: items.sort { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
            case .used: items.sort { ($0.lastAppliedAt ?? .distantPast) > ($1.lastAppliedAt ?? .distantPast) }
            case .name: items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .size: items.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
            }
        }
        return items
    }

    var body: some View {
        let items = filtered()
        let sources = Array(Set(base.map(\.source.label))).sorted()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    Header(title: title, subtitle: subtitle(items.count))
                    Spacer()
                    if mode == .downloaded {
                        Button { pickFiles() } label: { Label("Import…", systemImage: "plus") }
                        Button { NSWorkspace.shared.open(Paths.media) } label: { Label("Folder", systemImage: "folder") }
                    }
                    if !items.isEmpty {
                        Button { if let r = items.randomElement() { store.setWallpaper(r) } } label: { Label("Shuffle", systemImage: "shuffle") }
                    }
                }
                HStack(spacing: 10) {
                    TextField("Search title, credit or tag", text: $q).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                    if mode != .recents {
                        Picker("Sort", selection: $sort) { ForEach(LibSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            .frame(maxWidth: 220)
                    }
                }
                Chips(options: ["All", "Videos", "Photos"] + sources, selected: kind) { kind = $0 }
                if items.isEmpty { emptyState }
                Grid(items: items, selected: $selected)
            }.padding(24)
        }
        .overlay { if dropping { RoundedRectangle(cornerRadius: 16).stroke(accent, style: StrokeStyle(lineWidth: 3, dash: [10])).padding(8) } }
        .sheet(item: $selected) { DetailView(item: $0) }
    }
    @ViewBuilder private var emptyState: some View {
        if mode == .downloaded && base.isEmpty { firstRunDropZone } else { plainEmptyState }
    }
    private var firstRunDropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 54)).foregroundStyle(accent)
            Text("Drop videos or photos here").font(.title.bold())
            Text("4K videos (MP4, MOV, WebM, MKV…) and photos. Drop a whole folder if you like.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { pickFiles() } label: { Label("Import…", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(accent)
                Button { NSWorkspace.shared.open(Paths.media) } label: { Label("Open Lucid folder", systemImage: "folder") }
            }
            Text("Or drop files straight into the Lucid folder and they appear here on their own.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 56)
        .background(RoundedRectangle(cornerRadius: 20).strokeBorder(accent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [10])))
        .padding(.top, 20)
    }
    private var plainEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: mode == .favorites ? "heart" : mode == .recents ? "clock" : "sparkles.tv").font(.system(size: 44)).foregroundStyle(accent)
            Text(base.isEmpty ? "Nothing here yet" : "No matches").font(.title3.bold())
            Text(emptyHint).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 80)
    }
    private func subtitle(_ n: Int) -> String {
        switch mode {
        case .downloaded: return "\(n) on this Mac · \(ByteCountFormatter.string(fromByteCount: store.libraryBytes, countStyle: .file)) · hover a card → Apply. Drop your own videos/photos here."
        case .favorites: return "\(n) favorite\(n == 1 ? "" : "s") · tap ♥ on any wallpaper to add it here"
        case .recents: return "The last wallpapers you put on the desktop — reapply one with a click"
        }
    }
    private var emptyHint: String {
        switch mode {
        case .downloaded: return "Pick something in Discover → Set as Wallpaper, or drop a video/photo here."
        case .favorites: return "Hover any wallpaper and tap ♥."
        case .recents: return "Wallpapers you apply show up here."
        }
    }
    private func pickFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.allowedContentTypes = [.movie, .video, .image, .folder]
        if p.runModal() == .OK { store.importFiles(p.urls) }
    }
}

struct PlaylistView: View {
    let id: String
    @EnvironmentObject var store: Store
    @State private var selected: WallItem?
    @State private var renaming = false
    @State private var name = ""
    @State private var confirmDelete = false
    var body: some View {
        if let pl = store.playlists.first(where: { $0.id == id }) {
            content(pl)
        } else {
            Text("Playlist not found").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func content(_ pl: Playlist) -> some View {
        let active = store.activePlaylistID == id
        let sub = "\(pl.items.count) wallpaper\(pl.items.count == 1 ? "" : "s") · rotates every \(Store.intervalLabel(pl.minutes))" + (pl.shuffle ? " · shuffled" : " · in order") + (active ? " · PLAYING" : "")
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Header(title: pl.name, subtitle: sub)
                controls(pl, active: active)
                if pl.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list").font(.system(size: 40)).foregroundStyle(accent)
                        Text("Empty playlist").font(.title3.bold())
                        Text("Right-click any wallpaper → Add to Playlist → \(pl.name).").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 60)
                }
                Grid(items: pl.items.map { store.libraryItem($0.id) ?? $0 }, selected: $selected, playlistID: id)
            }.padding(24)
        }
        .sheet(item: $selected) { DetailView(item: $0) }
        .alert("Rename Playlist", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Save") { var p = pl; p.name = name.ifEmpty(pl.name); store.updatePlaylist(p) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(pl.name)”? Wallpapers stay in your library.", isPresented: $confirmDelete) {
            Button("Delete Playlist", role: .destructive) { store.deletePlaylist(id) }
        }
    }
    private func controls(_ pl: Playlist, active: Bool) -> some View {
        HStack(spacing: 12) {
            Button { active ? store.stopPlaylist() : store.playPlaylist(id) } label: {
                Label(active ? "Stop Playlist" : "Play Playlist", systemImage: active ? "stop.fill" : "play.fill")
            }.buttonStyle(.borderedProminent).tint(active ? .orange : accent.opacity(0.85)).disabled(pl.items.isEmpty)
            if active { Button { store.next() } label: { Label("Next", systemImage: "forward.fill") } }
            Toggle("Shuffle", isOn: Binding(get: { pl.shuffle }, set: { var p = pl; p.shuffle = $0; store.updatePlaylist(p) })).toggleStyle(.switch)
            Picker("Change every", selection: Binding(get: { pl.minutes }, set: { var p = pl; p.minutes = $0; store.updatePlaylist(p) })) {
                ForEach([5, 15, 30, 60, 180, 360, 1440], id: \.self) { Text(Store.intervalLabel($0)).tag($0) }
            }.frame(maxWidth: 220)
            Spacer()
            Menu {
                Button("Rename…") { name = pl.name; renaming = true }
                Button("Delete Playlist", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }.fixedSize()
        }
    }
}

struct DisplaysView: View {
    @EnvironmentObject var engine: WallpaperEngine
    @EnvironmentObject var store: Store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: "Displays", subtitle: "Each display gets its own looping player. New monitors follow the “All Displays” wallpaper automatically.")
                HStack {
                    Button { engine.togglePause() } label: {
                        Label(engine.state.userPaused ? "Resume All" : "Pause All", systemImage: engine.state.userPaused ? "play.fill" : "pause.fill")
                    }
                    Button { store.next() } label: { Label("Random from Library", systemImage: "shuffle") }
                    if let r = engine.pauseReason { Text("Paused: \(r)").foregroundStyle(.orange) }
                }
                let _ = engine.tick
                ForEach(NSScreen.screens, id: \.stableKey) { s in
                    let a = engine.assignment(for: s)
                    let lib = a.flatMap { store.libraryItem($0.itemID) }
                    HStack(spacing: 16) {
                        Color.clear.frame(width: 220, height: 124)
                            .overlay(RemoteImage(url: lib?.thumbURL, localPath: lib?.thumbPath))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.localizedName).font(.headline)
                            Text("\(s.pixelSize) · \(s == NSScreen.main ? "main display" : "secondary")").font(.caption).foregroundStyle(.secondary)
                            Text(a?.title ?? "No wallpaper from this app").font(.callout.weight(.medium))
                            if let a {
                                let paused = engine.screenPaused(s)
                                Label(a.kind == .image ? "Still image" : (paused.map { "Paused — \($0)" } ?? "Playing live"),
                                      systemImage: a.kind == .image ? "photo" : (paused == nil ? "play.circle.fill" : "pause.circle"))
                                    .foregroundStyle(a.kind == .image ? Color.secondary : (paused == nil ? accent : .orange)).font(.caption)
                                Text(engine.state.perScreen[s.stableKey] != nil ? "Set for this display only" : "Following “All Displays”")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if a != nil { Button("Clear") { engine.clear(screenKey: s.stableKey) } }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                }
            }.padding(24)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: WallpaperEngine
    @State private var battery = Pref.pauseOnBattery
    @State private var lowPower = Pref.pauseLowPower
    @State private var covered = Pref.pauseWhenCovered
    @State private var rotate = Pref.rotateMinutes
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var keyInput: [KeyName: String] = [:]
    @AppStorage("seamlessLoops") private var seamless = true
    @State private var speed = Pref.speed
    @State private var fill = Pref.fillScreen
    @State private var dim = Pref.dim
    @State private var watch = Pref.watchDownloads

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(title: "Settings", subtitle: "Playback, power saving and content sources.")
            GroupBox("Look") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Fit", selection: $fill) {
                        Text("Fill screen (crop edges)").tag(true); Text("Fit whole video (may letterbox)").tag(false)
                    }.pickerStyle(.radioGroup)
                        .onChange(of: fill) { _, v in Pref.fillScreen = v; engine.applyLook() }
                    Picker("Playback speed", selection: $speed) {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5], id: \.self) { Text(String(format: "%g×", $0)).tag($0) }
                    }.frame(maxWidth: 260)
                        .onChange(of: speed) { _, v in Pref.speed = v; engine.applyLook() }
                    HStack {
                        Text("Dim wallpaper")
                        Slider(value: $dim, in: 0...0.7).frame(maxWidth: 220)
                            .onChange(of: dim) { _, v in Pref.dim = v; engine.applyLook() }
                        Text("\(Int(dim * 100))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text("Dimming keeps desktop icons and widgets readable on bright wallpapers. Slower speed = calmer motion and less GPU.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("Adding wallpapers") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-add 4K videos and photos I download to ~/Downloads", isOn: $watch)
                        .onChange(of: watch) { _, v in Pref.watchDownloads = v; store.startDownloadsWatcher() }
                    Text("Only new files that are at least 3840×2160 are added; they're copied, so you can clear Downloads later. You can also drop files on the window or the Dock icon. Your library lives in ~/Library/Application Support/Lucid/Media.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("Power saving") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Pause when the desktop is fully covered (full-screen apps, maximized windows)", isOn: $covered)
                        .onChange(of: covered) { _, v in Pref.pauseWhenCovered = v; engine.updatePlayback() }
                    Toggle("Pause in Low Power Mode", isOn: $lowPower)
                        .onChange(of: lowPower) { _, v in Pref.pauseLowPower = v; engine.updatePlayback() }
                    Toggle("Pause whenever running on battery", isOn: $battery)
                        .onChange(of: battery) { _, v in Pref.pauseOnBattery = v; engine.updatePlayback() }
                    Text("Always paused while the screen is locked or asleep. Video is muted and hardware-decoded.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("General") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Auto-change wallpaper", selection: $rotate) {
                        Text("Never").tag(0); Text("Every 30 minutes").tag(30); Text("Every hour").tag(60)
                        Text("Every 6 hours").tag(360); Text("Daily").tag(1440)
                    }.frame(maxWidth: 340)
                        .onChange(of: rotate) { _, v in Pref.rotateMinutes = v; store.scheduleRotation() }
                    Toggle("Open at login", isOn: $login)
                        .onChange(of: login) { _, v in
                            do { if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                            catch { loginError = error.localizedDescription; login = SMAppService.mainApp.status == .enabled }
                        }
                    if let e = loginError { Text(e).font(.caption).foregroundStyle(.orange) }
                    Toggle("Make Space Live clips loop seamlessly (cross-fades the end into the start after download)", isOn: $seamless)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("Content sources (API keys stay in your Keychain)") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(KeyName.allCases, id: \.self) { k in
                        HStack {
                            Text(k.label).frame(width: 70, alignment: .leading)
                            if store.keysPresent.contains(k) {
                                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(accent)
                                Button("Remove") { store.saveKey(k, "") }
                            } else {
                                SecureField("Paste free API key", text: Binding(get: { keyInput[k] ?? "" }, set: { keyInput[k] = $0 }))
                                    .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                                Button("Save") { store.saveKey(k, keyInput[k] ?? ""); keyInput[k] = "" }
                                Link("Get key ↗", destination: k.signupURL)
                            }
                        }
                    }
                    Text("Apple Aerials, NASA and Wikimedia need no key. Every source is filtered to ≥3840×2160.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            GroupBox("Storage") {
                HStack {
                    Text("Downloaded: \(ByteCountFormatter.string(fromByteCount: store.libraryBytes, countStyle: .file))")
                    Spacer()
                    Button("Open Folder") { NSWorkspace.shared.open(Paths.media) }
                }.padding(6)
            }
            GroupBox("Licenses") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Apple Aerials: Apple content shipped with macOS — personal use on this Mac, no redistribution.")
                    Text("• NASA: generally public domain; credit NASA, don't imply endorsement.")
                    Text("• Pixabay: Pixabay Content License — free use; don't redistribute as-is.")
                    Text("• Wikimedia Commons: per-file license (often CC BY / CC BY-SA) shown on each item; credit the author if you share it.")
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var engine: WallpaperEngine
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(engine.state.all?.title ?? engine.state.perScreen.values.first?.title ?? "No wallpaper set")
        if let r = engine.pauseReason { Text("Paused — \(r)") }
        Divider()
        if let p = store.activePlaylist { Text("Playlist: \(p.name)") }
        Divider()
        Button(engine.state.userPaused ? "Resume" : "Pause") { engine.togglePause() }
        Button("Next Wallpaper") { store.next() }
        Button("Previous Wallpaper") { store.previous() }
        if let c = store.currentItem {
            Button(store.isFavorite(c.id) ? "Unfavorite Current" : "♥ Favorite Current") { store.toggleFavorite(c) }
        }
        if !store.favorites.isEmpty {
            Menu("Favorites") {
                ForEach(store.favorites.prefix(15)) { f in Button(f.title) { store.setWallpaper(store.libraryItem(f.id) ?? f) } }
            }
        }
        if !store.playlists.isEmpty {
            Menu("Play Playlist") {
                ForEach(store.playlists) { p in Button(p.name) { store.playPlaylist(p.id) } }
                if store.activePlaylist != nil { Divider(); Button("Stop Playlist") { store.stopPlaylist() } }
            }
        }
        Divider()
        Button("Open Lucid…") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Quit Lucid") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
