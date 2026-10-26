// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// The Home page as pure logic: which rows to show and in what order, the featured hero, the local usage counter,
// and the limit on how many live previews may play at once. No UI, no files, no network: fully unit-tested.
import Foundation

// MARK: - Usage counter (local only)

/// How many times each wallpaper was applied. Saved in usage.json in Lucid's own folder, used only to order the
/// "Most used" row. Never sent anywhere. Decoding is lenient: a bad entry is dropped, never the file.
struct UsageLog: Equatable {
    static let maxCount = 1_000_000
    static let maxEntries = 2000
    static let maxIDLength = 512
    private(set) var counts: [String: Int] = [:]

    var isEmpty: Bool { counts.isEmpty }
    func count(_ id: String) -> Int { counts[id] ?? 0 }
    mutating func record(_ id: String) {
        guard Self.validID(id) else { return }
        counts[id] = min(Self.maxCount, count(id) + 1)
        trim()
    }
    mutating func forget(_ id: String) { counts[id] = nil }

    private static func validID(_ id: String) -> Bool { !id.isEmpty && id.utf8.count <= maxIDLength }
    /// Keeps the most used entries when the log grows past `maxEntries`.
    private mutating func trim() {
        guard counts.count > Self.maxEntries else { return }
        let keep = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(Self.maxEntries)
        counts = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private struct File: Codable {
        var version = 1
        var counts: [String: Int]
    }
    /// Never throws: garbage or a wrong shape gives an empty log; each count must be a whole number ≥ 1.
    static func decode(_ d: Data) -> UsageLog {
        guard let obj = try? JSONSerialization.jsonObject(with: d), let top = obj as? [String: Any],
              let raw = top["counts"] as? [String: Any] else { return UsageLog() }
        var u = UsageLog()
        for (k, v) in raw where validID(k) {
            guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { continue }
            let x = n.doubleValue
            guard x.isFinite, x >= 1, x.rounded() == x else { continue }
            u.counts[k] = x >= Double(maxCount) ? maxCount : Int(x)
        }
        u.trim()
        return u
    }
    func encoded() -> Data? {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return try? e.encode(File(counts: counts))
    }
}

// MARK: - Rows

struct HomeRow: Identifiable, Equatable {
    enum Kind: Equatable { case continueWatching, mostUsed, featured, favorites, recentlyAdded, category(String) }
    let kind: Kind
    let title: String
    let subtitle: String
    let items: [WallItem]
    var id: String {
        switch kind {
        case .category(let c): return "category:" + c
        default: return "\(kind)"
        }
    }
}

struct HomeInput {
    var library: [WallItem]
    var live: [WallItem]
    var aerials: [WallItem]
    var favorites: [WallItem]
    var usage: UsageLog
    var featuredIDs: [String]     // curated order from catalog.json ("featured": true), never popularity
    var themes: [String]          // Live 4K category order
    var now: Date
    var isReady: (WallItem) -> Bool   // the file is on this Mac
    var theme: (WallItem) -> String   // Live 4K category of a catalog clip
}

enum HomeBuilder {
    static let rowLimit = 20
    static let newWithinDays = 14.0
    static let aerialsTitle = "Apple Aerials"
    static let myFilesTitle = "My Files"

    /// Rows in display order; empty rows are left out (a fresh install gets Featured + categories only).
    static func rows(_ i: HomeInput) -> [HomeRow] {
        let resolve = resolver(i)
        var out: [HomeRow] = []
        func add(_ k: HomeRow.Kind, _ title: String, _ sub: String, _ items: [WallItem]) {
            var seen = Set<String>()
            let unique = items.filter { seen.insert($0.id).inserted }.prefix(rowLimit)
            if !unique.isEmpty { out.append(HomeRow(kind: k, title: title, subtitle: sub, items: Array(unique))) }
        }
        let ready = i.library.filter(i.isReady)
        add(.continueWatching, "Recently used", "Pick up where you left off",
            ready.filter { $0.lastAppliedAt != nil }.sorted { $0.lastAppliedAt! > $1.lastAppliedAt! })
        if i.usage.counts.values.contains(where: { $0 >= 2 }) {
            let used = i.usage.counts.keys.compactMap { resolve($0) }.filter { i.usage.count($0.id) > 0 }
            add(.mostUsed, "Most used", "Counted on this Mac only",
                used.sorted { a, b in
                    let (x, y) = (i.usage.count(a.id), i.usage.count(b.id))
                    if x != y { return x > y }
                    return (a.lastAppliedAt ?? .distantPast, a.id) > (b.lastAppliedAt ?? .distantPast, b.id)
                })
        }
        add(.featured, "Featured", "Hand-picked by Lucid", featured(i, resolve))
        add(.favorites, "Favorites", "Everything you ♥", i.favorites.map { resolve($0.id) ?? $0 })
        let cutoff = i.now.addingTimeInterval(-newWithinDays * 86400)
        add(.recentlyAdded, "New in your library", "Added in the last two weeks",
            ready.filter { ($0.addedAt ?? .distantPast) >= cutoff }.sorted { $0.addedAt! > $1.addedAt! })
        for t in i.themes {
            add(.category(t), t, "Live 4K", i.live.filter { i.theme($0) == t }.map { resolve($0.id) ?? $0 })
        }
        let aer = i.aerials.map { resolve($0.id) ?? $0 }
        add(.category(aerialsTitle), aerialsTitle, "Apple's own 4K films · on this Mac first",
            aer.filter(i.isReady) + aer.filter { !i.isReady($0) })
        add(.category(myFilesTitle), myFilesTitle, "Your own videos and photos",
            ready.filter { $0.source == .local }.sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) })
        return out
    }

    /// The big item at the top: the first featured clip already on this Mac (so it can play), else a video on this
    /// Mac (most recently used first), else the first featured poster, else the first catalog clip.
    static func hero(_ i: HomeInput) -> WallItem? {
        let resolve = resolver(i)
        let feat = featured(i, resolve)
        if let f = feat.first(where: { $0.kind == .video && i.isReady($0) }) { return f }
        let videos = i.library.filter { $0.kind == .video && i.isReady($0) }
            .sorted { ($0.lastAppliedAt ?? .distantPast) > ($1.lastAppliedAt ?? .distantPast) }
        return videos.first ?? feat.first ?? i.live.first.map { resolve($0.id) ?? $0 }
    }

    private static func featured(_ i: HomeInput, _ resolve: (String) -> WallItem?) -> [WallItem] {
        var seen = Set<String>()
        return i.featuredIDs.filter { seen.insert($0).inserted }.compactMap(resolve)
    }
    /// The library copy wins (it has the local file, thumbnail and options), then the catalogs.
    private static func resolver(_ i: HomeInput) -> (String) -> WallItem? {
        var byID: [String: WallItem] = [:]
        for it in i.aerials + i.live + i.favorites + i.library { byID[it.id] = it }   // later wins: library last
        return { byID[$0] }
    }
}

// MARK: - Live previews

/// At most `capacity` preview players exist at once. Pinned slots (the Home hero, the detail sheet) are never taken
/// by a hover; a hover takes the oldest hover's slot. Disabled (window hidden, Reduce Motion, smart pause) = none.
struct PreviewSlots {
    let capacity: Int
    private(set) var active: [String] = []   // oldest first
    private(set) var pinned: Set<String> = []
    private(set) var enabled = true
    init(capacity: Int) { self.capacity = max(1, capacity) }

    func isActive(_ id: String) -> Bool { active.contains(id) }
    mutating func request(_ id: String, pinned pin: Bool = false) -> (granted: Bool, evicted: [String]) {
        guard enabled else { return (false, []) }
        if active.contains(id) {
            if pin { pinned.insert(id) }
            return (true, [])
        }
        var evicted: [String] = []
        if active.count >= capacity {
            guard let victim = active.first(where: { !pinned.contains($0) }) else { return (false, []) }
            active.removeAll { $0 == victim }
            evicted.append(victim)
        }
        active.append(id)
        if pin { pinned.insert(id) }
        return (true, evicted)
    }
    mutating func release(_ id: String) { active.removeAll { $0 == id }; pinned.remove(id) }
    /// Turning off returns every id that must stop now.
    mutating func setEnabled(_ on: Bool) -> [String] {
        enabled = on
        guard !on else { return [] }
        let all = active
        active = []; pinned = []
        return all
    }
}

enum PreviewPolicy {
    /// Previews play only while the Lucid window is visible and Lucid is the frontmost app, Reduce Motion is off,
    /// and the wallpaper isn't smart-paused (battery, Low Power, heat, CPU, lock, sleep). A wallpaper the user paused
    /// by hand doesn't stop browsing.
    static func shouldPlay(windowVisible: Bool, appActive: Bool, reduceMotion: Bool, pause: PauseReason?) -> Bool {
        guard windowVisible, appActive, !reduceMotion else { return false }
        switch pause {
        case nil, .user?, .covered?: return true
        default: return false
        }
    }
    /// The file a preview may play: only a video already on this Mac. Remote clips show their poster (no network).
    static func previewPath(_ it: WallItem) -> String? {
        guard it.kind == .video, let p = it.localPath, p.hasPrefix("/") else { return nil }
        return p
    }
}
