// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Saved data from Lucid 1.1.1, and from 1.2.0 development builds, must still load.
import Foundation

private func compatFixture(_ name: String) throws -> Data {
    let root = ProcessInfo.processInfo.environment["LUCID_FIXTURES"] ?? "Tests/Fixtures"
    return try Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("compat").appendingPathComponent(name))
}

func registerModelCompatTests() {
    test("Compat: a 1.1.1 state.json (no reactive, no Day/Night) still decodes") {
        let old = #"{"all":{"itemID":"live:1","title":"Nebula","path":"/tmp/a.mp4","kind":"video"},"perScreen":{},"userPaused":false}"#
        let s = try JSONDecoder().decode(EngineState.self, from: Data(old.utf8))
        expectEqual(s.all?.title, "Nebula")
        expectEqual(s.all?.reactive, nil)
        expect(s.dayNight == nil)
        expectEqual(SavedData.state(Data(old.utf8))?.all?.title, "Nebula")
    }
    test("Compat: a 1.1.1 library item still decodes and round-trips") {
        let old = #"[{"id":"local:x","source":"local","kind":"image","title":"X","width":3840,"height":2160}]"#
        let l = SavedData.items(Data(old.utf8))
        expectEqual(l.map(\.id), ["local:x"])
        let back = try JSONDecoder().decode(WallItem.self, from: JSONEncoder().encode(l[0]))
        expectEqual(back, l[0])
    }
    test("Compat: Day/Night rules and reactive looks survive a save/load (relaunch)") {
        var s = EngineState()
        let d = Assignment(itemID: "d", title: "Day", path: "/d.mp4", kind: .video, reactive: ReactiveOptions(pulse: true))
        let n = Assignment(itemID: "n", title: "Night", path: "/n.png", kind: .image)
        s.dayNight = [EngineState.allKey: DayNightRule(day: d, night: n)]
        let back = try JSONDecoder().decode(EngineState.self, from: JSONEncoder().encode(s))
        expectEqual(back.dayNight?[EngineState.allKey]?.pick(.day), d)
        expectEqual(back.dayNight?[EngineState.allKey]?.pick(.night), n)
        expect(d.sameMedia(Assignment(itemID: "d", title: "Day", path: "/d.mp4", kind: .video)), "look options don't count as new media")
        expect(!d.sameMedia(n))
    }
    test("Compat: dev-build library.json drops items from removed sources and keeps the rest") {
        let l = SavedData.items(try compatFixture("dev-1.2.0-library.json"))
        expectEqual(l.map(\.id), ["local:x", "nasa:1"])
    }
    test("Compat: an unknown source or kind drops only that item, not the whole file") {
        let j = #"[{"id":"a","source":"local","kind":"image","title":"A","width":1,"height":1},"#
            + #"{"id":"b","source":"someFutureSource","kind":"image","title":"B","width":1,"height":1},"#
            + #"{"id":"c","source":"local","kind":"hologram","title":"C","width":1,"height":1},"#
            + #""oops",{"id":"d","source":"nasa","kind":"image","title":"D","width":1,"height":1}]"#
        expectEqual(SavedData.items(Data(j.utf8)).map(\.id), ["a", "d"])
        expectEqual(SavedData.items(Data("not json".utf8)).count, 0)
    }
    test("Compat: dev-build playlists.json keeps the playlist and drops removed-source items") {
        let p = SavedData.playlists(try compatFixture("dev-1.2.0-playlists.json"))
        expectEqual(p.map(\.name), ["Mix"])
        expectEqual(p.first?.items.map(\.id), ["local:x"])
        expectEqual(p.first?.minutes, 30)
    }
    test("Compat: dev-build state.json drops web assignments and Day/Night rules using them") {
        guard let s = SavedData.state(try compatFixture("dev-1.2.0-state.json")) else { expect(false, "state did not decode"); return }
        expect(s.all == nil, "the web 'all displays' assignment is dropped")
        expectEqual(s.perScreen.keys.sorted(), ["A"])
        expectEqual(s.perScreen["A"]?.reactive, ReactiveOptions(pulse: true))
        expectEqual(s.dayNight?.keys.sorted(), ["A"], "the rule with a web side is dropped, the image/video rule is kept")
        expectEqual(s.dayNight?["A"]?.day.kind, .image)
        expectEqual(s.userPaused, true)
    }
}
