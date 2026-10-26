// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Home page rows, the local usage counter, the hero pick and the live-preview slot limit.
import Foundation

private func item(_ id: String, _ source: Source = .live, kind: Kind = .video, title: String? = nil, category: String? = nil,
                  applied: Date? = nil, added: Date? = nil, path: String? = nil) -> WallItem {
    var it = WallItem(id: id, source: source, kind: kind, title: title ?? id, width: 3840, height: 2160, category: category)
    it.lastAppliedAt = applied; it.addedAt = added; it.localPath = path
    return it
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// Ready = has a localPath (the app checks the file exists; tests inject that).
private func input(library: [WallItem] = [], live: [WallItem] = [], aerials: [WallItem] = [], favorites: [WallItem] = [],
                   usage: UsageLog = UsageLog(), featured: [String] = []) -> HomeInput {
    HomeInput(library: library, live: live, aerials: aerials, favorites: favorites, usage: usage, featuredIDs: featured,
              themes: ["Space", "Ocean & Beaches"], now: t0,
              isReady: { $0.localPath != nil }, theme: { $0.category ?? "Space" })
}

func registerHomeTests() {
    // MARK: usage counter
    test("usage: record counts up per id and ignores empty ids") {
        var u = UsageLog()
        u.record("a"); u.record("a"); u.record("b"); u.record("")
        expectEqual(u.count("a"), 2); expectEqual(u.count("b"), 1); expectEqual(u.count("zzz"), 0)
        expectEqual(u.counts.count, 2)
    }
    test("usage: round-trips through its saved JSON") {
        var u = UsageLog(); u.record("live:x"); u.record("live:x"); u.record("local:y")
        guard let d = u.encoded() else { expect(false, "encode"); return }
        expectEqual(UsageLog.decode(d), u)
    }
    test("usage: lenient decode drops bad entries, never the file") {
        let json = #"{"version":1,"counts":{"good":3,"neg":-2,"text":"7","frac":2.5,"bool":true,"huge":99999999999,"zero":0,"ok2":1}}"#
        let u = UsageLog.decode(Data(json.utf8))
        expectEqual(u.count("good"), 3); expectEqual(u.count("ok2"), 1)
        expectEqual(u.count("neg"), 0); expectEqual(u.count("text"), 0); expectEqual(u.count("frac"), 0); expectEqual(u.count("bool"), 0)
        expectEqual(u.count("zero"), 0)
        expectEqual(u.count("huge"), UsageLog.maxCount, "clamped")
    }
    test("usage: garbage, wrong shapes and empty data decode to an empty log") {
        for s in ["", "not json", "[]", "null", #"{"counts":[1,2]}"#, #"{"counts":"x"}"#, #"{"version":"9"}"#] {
            expect(UsageLog.decode(Data(s.utf8)).isEmpty, "input \(s)")
        }
    }
    test("usage: overlong ids are dropped and the log is capped to the most used entries") {
        var u = UsageLog()
        u.record(String(repeating: "x", count: UsageLog.maxIDLength + 1))
        expect(u.isEmpty)
        var counts: [String: Int] = [:]
        for i in 0..<(UsageLog.maxEntries + 50) { counts["id\(i)"] = i + 1 }
        let d = try JSONSerialization.data(withJSONObject: ["version": 1, "counts": counts])
        let big = UsageLog.decode(d)
        expectEqual(big.counts.count, UsageLog.maxEntries)
        expectEqual(big.count("id0"), 0, "least used dropped first")
        expectEqual(big.count("id\(UsageLog.maxEntries + 49)"), UsageLog.maxEntries + 50)
    }

    // MARK: rows
    test("home: a fresh install shows Featured and categories, hides Continue, Most used, Favorites, New and My Files") {
        let live = [item("live:a", category: "Space"), item("live:b", category: "Ocean & Beaches"), item("live:c", category: "Space")]
        let aer = [item("aerials:1", .aerials)]
        let rows = HomeBuilder.rows(input(live: live, aerials: aer, featured: ["live:c", "live:a"]))
        expectEqual(rows.map(\.kind), [.featured, .category("Space"), .category("Ocean & Beaches"), .category("Apple Aerials")])
        expectEqual(rows.first?.items.map(\.id), ["live:c", "live:a"], "curated featured order kept")
        expectEqual(rows.first { $0.kind == .category("Space") }?.items.map(\.id), ["live:a", "live:c"], "category keeps catalog order")
    }
    test("home: empty everything gives no rows and no hero") {
        expect(HomeBuilder.rows(input()).isEmpty)
        expect(HomeBuilder.hero(input()) == nil)
    }
    test("home: Continue is newest-applied first, only items on this Mac") {
        let lib = [item("a", applied: t0.addingTimeInterval(-300), path: "/a"), item("b", applied: t0.addingTimeInterval(-10), path: "/b"),
                   item("gone", applied: t0, path: nil), item("never", path: "/n")]
        let rows = HomeBuilder.rows(input(library: lib))
        expectEqual(rows.first?.kind, .continueWatching)
        expectEqual(rows.first?.items.map(\.id), ["b", "a"])
    }
    test("home: Most used appears only once something was applied twice, ranked by count") {
        var u = UsageLog(); u.record("a"); u.record("b")
        let lib = [item("a", applied: t0, path: "/a"), item("b", applied: t0.addingTimeInterval(-5), path: "/b")]
        expect(!HomeBuilder.rows(input(library: lib, usage: u)).contains { $0.kind == .mostUsed }, "all once = same as Continue, hidden")
        u.record("b"); u.record("b"); u.record("removed-item"); u.record("removed-item"); u.record("removed-item")
        let row = HomeBuilder.rows(input(library: lib, usage: u)).first { $0.kind == .mostUsed }
        expectEqual(row?.items.map(\.id), ["b", "a"], "unknown ids skipped, count order")
    }
    test("home: catalog items show their downloaded library copy (local path, options)") {
        let lib = [item("live:a", category: "Space", path: "/media/a.mp4")]
        let rows = HomeBuilder.rows(input(library: lib, live: [item("live:a", category: "Space")], featured: ["live:a"]))
        expectEqual(rows.first { $0.kind == .featured }?.items.first?.localPath, "/media/a.mp4")
        expectEqual(rows.first { $0.kind == .category("Space") }?.items.first?.localPath, "/media/a.mp4")
    }
    test("home: Favorites, New (added in the last 14 days) and My Files rows") {
        let mine = item("local:x", .local, kind: .image, added: t0.addingTimeInterval(-3600), path: "/x")
        let old = item("local:old", .local, kind: .image, added: t0.addingTimeInterval(-30 * 86400), path: "/o")
        let rows = HomeBuilder.rows(input(library: [mine, old], favorites: [item("live:f")]))
        expectEqual(rows.first { $0.kind == .favorites }?.items.map(\.id), ["live:f"])
        expectEqual(rows.first { $0.kind == .recentlyAdded }?.items.map(\.id), ["local:x"])
        expectEqual(rows.first { $0.kind == .category("My Files") }?.items.map(\.id), ["local:x", "local:old"])
    }
    test("home: Apple Aerials row puts films already on this Mac first, otherwise keeps order") {
        let aer = [item("aerials:1", .aerials), item("aerials:2", .aerials, path: "/v2"), item("aerials:3", .aerials), item("aerials:4", .aerials, path: "/v4")]
        let row = HomeBuilder.rows(input(aerials: aer)).first { $0.kind == .category("Apple Aerials") }
        expectEqual(row?.items.map(\.id), ["aerials:2", "aerials:4", "aerials:1", "aerials:3"])
    }
    test("home: rows are capped and every row and id is unique") {
        let live = (0..<100).map { item("live:\($0)", category: "Space") }
        let rows = HomeBuilder.rows(input(live: live, featured: ["live:1", "live:1", "missing"]))
        expectEqual(rows.first { $0.kind == .category("Space") }?.items.count, HomeBuilder.rowLimit)
        expectEqual(rows.first { $0.kind == .featured }?.items.map(\.id), ["live:1"], "duplicates and unknown featured ids dropped")
        expectEqual(Set(rows.map(\.id)).count, rows.count)
        expect(rows.allSatisfy { r in Set(r.items.map(\.id)).count == r.items.count })
    }

    // MARK: hero
    test("hero: first featured clip already on this Mac, so it can play") {
        let lib = [item("live:b", path: "/b.mp4")]
        let live = [item("live:a"), item("live:b"), item("live:c")]
        expectEqual(HomeBuilder.hero(input(library: lib, live: live, featured: ["live:a", "live:b"]))?.id, "live:b")
    }
    test("hero: no featured clip on this Mac -> any video on this Mac, then the first featured poster") {
        let mine = item("local:v", .local, applied: t0, path: "/v.mov")
        let photo = item("local:p", .local, kind: .image, applied: t0, path: "/p.jpg")
        expectEqual(HomeBuilder.hero(input(library: [photo, mine], live: [item("live:a")], featured: ["live:a"]))?.id, "local:v")
        expectEqual(HomeBuilder.hero(input(live: [item("live:a")], featured: ["live:a"]))?.id, "live:a")
        expectEqual(HomeBuilder.hero(input(live: [item("live:z")]))?.id, "live:z", "no featured flag at all: first catalog clip")
    }

    // MARK: preview slots
    test("slots: never more than capacity players; oldest hover is evicted first") {
        var s = PreviewSlots(capacity: 3)
        expect(s.request("a").granted); expect(s.request("b").granted); expect(s.request("c").granted)
        let r = s.request("d")
        expect(r.granted); expectEqual(r.evicted, ["a"]); expectEqual(s.active, ["b", "c", "d"])
        expect(s.active.count <= 3)
    }
    test("slots: pinned hero/detail players are never evicted by hovers; hovers are refused when only pins remain") {
        var s = PreviewSlots(capacity: 2)
        expect(s.request("hero", pinned: true).granted)
        expect(s.request("h1").granted)
        let r = s.request("h2"); expectEqual(r.evicted, ["h1"]); expect(r.granted)
        expect(s.request("detail", pinned: true).granted)
        expectEqual(Set(s.active), ["hero", "detail"])
        expect(!s.request("h3").granted, "no free slot and only pins")
        s.release("detail")
        expect(s.request("h3").granted)
    }
    test("slots: re-requesting is idempotent, release frees, disabling stops everything and refuses new players") {
        var s = PreviewSlots(capacity: 3)
        _ = s.request("a"); _ = s.request("a")
        expectEqual(s.active, ["a"])
        s.release("a"); s.release("nope")
        expect(s.active.isEmpty)
        _ = s.request("a"); _ = s.request("p", pinned: true)
        expectEqual(Set(s.setEnabled(false)), ["a", "p"])
        expect(s.active.isEmpty)
        expect(!s.request("b").granted)
        _ = s.setEnabled(true)
        expect(s.request("b").granted)
    }
    test("preview gate: plays only when visible, frontmost, motion allowed and not smart-paused") {
        expect(PreviewPolicy.shouldPlay(windowVisible: true, appActive: true, reduceMotion: false, pause: nil))
        expect(PreviewPolicy.shouldPlay(windowVisible: true, appActive: true, reduceMotion: false, pause: .user), "a paused wallpaper doesn't stop browsing")
        expect(!PreviewPolicy.shouldPlay(windowVisible: false, appActive: true, reduceMotion: false, pause: nil))
        expect(!PreviewPolicy.shouldPlay(windowVisible: true, appActive: false, reduceMotion: false, pause: nil))
        expect(!PreviewPolicy.shouldPlay(windowVisible: true, appActive: true, reduceMotion: true, pause: nil))
        for p in PauseReason.allCases where p != .user && p != .covered {
            expect(!PreviewPolicy.shouldPlay(windowVisible: true, appActive: true, reduceMotion: false, pause: p), "\(p)")
        }
    }
    test("preview: only a clip already on this Mac is ever previewed (no network)") {
        expectEqual(PreviewPolicy.previewPath(item("live:a")), nil)
        var remote = item("live:r"); remote.previewURL = "https://example.org/x.mp4"
        expectEqual(PreviewPolicy.previewPath(remote), nil)
        expectEqual(PreviewPolicy.previewPath(item("x", path: "/m/x.mov")), "/m/x.mov")
        expectEqual(PreviewPolicy.previewPath(item("p", kind: .image, path: "/m/p.jpg")), nil, "photos are posters")
    }
}
