// Content providers. Every provider enforces the 3840×2160 minimum.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

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
