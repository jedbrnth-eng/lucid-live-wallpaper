// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Four-phase day (dawn, day, dusk, night) on top of the 1.2.0 Day/Night logic, and saved 1.2.0 rules still working.
// Reference civil twilight: api.sunrise-sunset.org (fetched 2026-10-26), tolerance ±2 minutes.
import Foundation

private func z(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

func registerFourPhaseTests() {
    let bkk = TimeZone(identifier: "Asia/Bangkok")!
    let auto = DayNightSchedule(mode: .sun(latitude: 13.7563, longitude: 100.5018), timeZone: bkk)

    test("Twilight: Bangkok 2026-10-26 civil dawn 05:49:06 and civil dusk 18:14:51 local") {
        guard case .normal(let a, let b)? = SunTimes.elevationEvents(year: 2026, month: 10, day: 26, latitude: 13.7563, longitude: 100.5018, elevation: -6) else {
            expect(false, "expected civil twilight"); return
        }
        expectNear(a.timeIntervalSince(z("2026-10-25T22:49:06Z")), 0, 120)
        expectNear(b.timeIntervalSince(z("2026-10-26T11:14:51Z")), 0, 120)
    }
    test("Twilight: London midwinter civil dawn 07:23:28Z, dusk 16:33:40Z") {
        guard case .normal(let a, let b)? = SunTimes.elevationEvents(year: 2026, month: 12, day: 21, latitude: 51.5074, longitude: -0.1278, elevation: -6) else {
            expect(false); return
        }
        expectNear(a.timeIntervalSince(z("2026-12-21T07:23:28Z")), 0, 120)
        expectNear(b.timeIntervalSince(z("2026-12-21T16:33:40Z")), 0, 120)
    }
    test("Four phases: Bangkok through a day (dawn from civil dawn to sun +6°, dusk from +6° to civil dusk)") {
        expectEqual(auto.part(at: z("2026-10-25T22:30:00Z")), .night, "05:30 local")
        expectEqual(auto.part(at: z("2026-10-25T22:55:00Z")), .dawn, "05:55, before sunrise")
        expectEqual(auto.part(at: z("2026-10-25T23:20:00Z")), .dawn, "06:20, just after sunrise")
        expectEqual(auto.part(at: z("2026-10-26T00:00:00Z")), .day, "07:00")
        expectEqual(auto.part(at: z("2026-10-26T10:45:00Z")), .dusk, "17:45, before sunset")
        expectEqual(auto.part(at: z("2026-10-26T11:05:00Z")), .dusk, "18:05, after sunset")
        expectEqual(auto.part(at: z("2026-10-26T11:30:00Z")), .night, "18:30")
    }
    test("Four phases: polar day and polar night stay day / night") {
        let s = DayNightSchedule(mode: .sun(latitude: 69.6492, longitude: 18.9553), timeZone: TimeZone(identifier: "Europe/Oslo")!)
        expectEqual(s.part(at: z("2026-06-21T22:00:00Z")), .day)
        expectEqual(s.part(at: z("2026-12-21T00:00:00Z")), .night)
    }
    test("Four phases: fixed times give a dawn hour after day starts and a dusk hour before night") {
        let m = DayNightSchedule(mode: .manual(dayStartMinute: 7 * 60, nightStartMinute: 19 * 60), timeZone: bkk)
        expectEqual(m.part(at: z("2026-10-26T00:30:00Z")), .dawn, "07:30")
        expectEqual(m.part(at: z("2026-10-26T05:00:00Z")), .day, "12:00")
        expectEqual(m.part(at: z("2026-10-26T11:30:00Z")), .dusk, "18:30")
        expectEqual(m.part(at: z("2026-10-26T13:00:00Z")), .night, "20:00")
        expectEqual(m.phase(at: z("2026-10-26T00:30:00Z")), .day, "two-phase answer unchanged")
    }
    test("Four phases: next boundary includes twilight and golden-hour edges") {
        let after = z("2026-10-25T22:00:00Z")   // 05:00 local
        guard let n = auto.nextBoundary(after: after) else { expect(false); return }
        expectNear(n.timeIntervalSince(z("2026-10-25T22:49:06Z")), 0, 120, "civil dawn comes first")
        let all = (0..<6).reduce(into: [after]) { acc, _ in if let x = auto.nextBoundary(after: acc.last!) { acc.append(x) } }
        expect(zip(all, all.dropFirst()).allSatisfy { $0 < $1 }, "strictly increasing")
    }

    let d = Assignment(itemID: "d", title: "Day", path: "/d.mp4", kind: .video)
    let n = Assignment(itemID: "n", title: "Night", path: "/n.mp4", kind: .video)
    let dawn = Assignment(itemID: "a", title: "Dawn", path: "/a.mp4", kind: .video)
    test("Rules: without dawn/dusk wallpapers a rule behaves exactly like 1.2.0") {
        let r = DayNightRule(day: d, night: n)
        expectEqual(r.pick(.night, part: .dawn), n, "before sunrise is still night")
        expectEqual(r.pick(.day, part: .dawn), d, "after sunrise is still day")
        expectEqual(r.pick(.day, part: .dusk), d)
        expectEqual(r.pick(.night, part: .dusk), n)
        expectEqual(r.pick(.day), d)
    }
    test("Rules: dawn/dusk wallpapers are used in their window") {
        var r = DayNightRule(day: d, night: n); r.dawn = dawn
        expectEqual(r.pick(.night, part: .dawn), dawn)
        expectEqual(r.pick(.night, part: .dusk), n, "no dusk wallpaper: falls back")
    }
    test("Rules: a saved 1.2.0 rule loads; a broken dawn side drops only that side") {
        let old = #"{"day":{"itemID":"d","title":"Day","path":"/d.mp4","kind":"video"},"night":{"itemID":"n","title":"Night","path":"/n.mp4","kind":"video"}}"#
        let r = try JSONDecoder().decode(DayNightRule.self, from: Data(old.utf8))
        expectEqual(r.dawn, nil); expectEqual(r.dusk, nil); expectEqual(r.night, n)
        let broken = #"{"day":{"itemID":"d","title":"Day","path":"/d.mp4","kind":"video"},"night":{"itemID":"n","title":"Night","path":"/n.mp4","kind":"video"},"dawn":{"kind":"hologram"}}"#
        let b = try JSONDecoder().decode(DayNightRule.self, from: Data(broken.utf8))
        expectEqual(b.dawn, nil); expectEqual(b.day, d)
        var full = DayNightRule(day: d, night: n); full.dawn = dawn; full.dusk = n
        expectEqual(try JSONDecoder().decode(DayNightRule.self, from: JSONEncoder().encode(full)), full)
    }
}
