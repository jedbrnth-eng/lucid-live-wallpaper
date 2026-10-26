// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Saved data from Lucid 1.1.1 must still load after the new fields (reactive looks, Day/Night, Wallpaper Engine).
import Foundation

func registerModelCompatTests() {
    test("Compat: a 1.1.1 state.json (no reactive, no Day/Night) still decodes") {
        let old = #"{"all":{"itemID":"live:1","title":"Nebula","path":"/tmp/a.mp4","kind":"video"},"perScreen":{},"userPaused":false}"#
        let s = try JSONDecoder().decode(EngineState.self, from: Data(old.utf8))
        expectEqual(s.all?.title, "Nebula")
        expectEqual(s.all?.reactive, nil)
        expect(s.dayNight == nil)
    }
    test("Compat: a 1.1.1 library item still decodes, and new kinds/sources round-trip") {
        let old = #"[{"id":"local:x","source":"local","kind":"image","title":"X","width":3840,"height":2160}]"#
        let l = try JSONDecoder().decode([WallItem].self, from: Data(old.utf8))
        expectEqual(l.first?.weSupport, nil)
        var it = l[0]; it.source = .wallpaperEngine; it.kind = .web; it.weSupport = .web
        let back = try JSONDecoder().decode(WallItem.self, from: JSONEncoder().encode(it))
        expectEqual(back, it)
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
}
