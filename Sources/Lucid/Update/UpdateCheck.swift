// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Optional "is there a newer Lucid?" check (off by default): asks GitHub's public releases API at most once a
// day, sends nothing about you, never downloads or installs anything. Pure parsing and version logic here;
// the request lives in UpdateChecker.swift.
import Foundation

struct ReleaseInfo: Equatable {
    var version: String
    var page: URL
}

enum UpdateCheck {
    static let repo = "jedbrnth-eng/lucid-live-wallpaper"
    static let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")
    static let maxBytes = 512 * 1024
    static let interval: TimeInterval = 24 * 3600

    /// "v1.3.1" / "1.3.1" -> [1, 3, 1]; anything else (pre-release suffixes included) -> nil.
    static func components(_ v: String) -> [Int]? {
        let s = v.hasPrefix("v") ? String(v.dropFirst()) : v
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        let n = parts.compactMap { p -> Int? in p.allSatisfy(\.isASCII) && p.allSatisfy(\.isNumber) && p.count <= 6 ? Int(p) : nil }
        return n.count == parts.count ? n : nil
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = components(candidate), let b = components(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The published (non-draft, non-pre-release) latest release, only if its page is our repo on github.com over HTTPS.
    static func parse(_ d: Data) -> ReleaseInfo? {
        guard !d.isEmpty, d.count <= maxBytes,
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let tag = j["tag_name"] as? String, let page = j["html_url"] as? String,
              (j["draft"] as? Bool) != true, (j["prerelease"] as? Bool) != true,
              let comps = components(tag),
              let u = URL(string: page), isReleasePage(u) else { return nil }
        return ReleaseInfo(version: comps.map(String.init).joined(separator: "."), page: u)
    }

    /// Exactly https://github.com/<repo>/releases/tag/<tag>: no user info, port, query, fragment, `.`/`..` or
    /// percent-escapes, so what a browser opens after normalising is the same page we checked.
    static func isReleasePage(_ u: URL) -> Bool {
        guard let c = URLComponents(url: u, resolvingAgainstBaseURL: false), c.scheme == "https", c.host == "github.com",
              c.user == nil, c.password == nil, c.port == nil, c.query == nil, c.fragment == nil,
              !c.percentEncodedPath.contains("%") else { return false }
        let parts = c.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let want = ["", repo.split(separator: "/").map(String.init)[0], repo.split(separator: "/").map(String.init)[1], "releases", "tag"]
        guard parts.count == 6, Array(parts.prefix(5)) == want, !parts[5].isEmpty, parts[5] != ".", parts[5] != ".." else { return false }
        return true
    }

    static func shouldCheck(enabled: Bool, last: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let l = last else { return true }
        return now < l || now.timeIntervalSince(l) >= interval
    }
}
