// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// "Pick for me" in Day & Night: the light in each wallpaper decides where it goes.
import Foundation

func registerSunPickerTests() {
    func c(_ id: String, _ title: String, luma: Double, warmth: Double, sat: Double = 0.3) -> SunCandidate {
        SunCandidate(id: id, title: title, light: LightStats(luma: luma, warmth: warmth, saturation: sat))
    }
    let starfield = c("stars", "Pillars", luma: 0.06, warmth: -0.05)
    let noon = c("noon", "Ridge", luma: 0.72, warmth: -0.08)
    let ember = c("ember", "Harbour", luma: 0.38, warmth: 0.42)
    let rose = c("rose", "Bay", luma: 0.45, warmth: 0.2)
    let grey = c("grey", "Concrete", luma: 0.5, warmth: 0)

    test("Sun picks: light from pixels (brightness, warm vs cool, colourfulness)") {
        let white = LightStats.from(rgba: [255, 255, 255, 255, 255, 255, 255, 255])
        expectNear(white?.luma ?? -1, 1, 0.001); expectNear(white?.warmth ?? -1, 0, 0.001); expectNear(white?.saturation ?? -1, 0, 0.001)
        let orange = LightStats.from(rgba: [255, 128, 0, 255])
        expectNear(orange?.warmth ?? 0, 1, 0.001, "red minus blue")
        expectNear(orange?.luma ?? 0, 0.2126 + 0.7152 * 128 / 255, 0.001)
        expectNear(orange?.saturation ?? 0, 1, 0.001)
        expectNear(LightStats.from(rgba: [0, 0, 255, 255])?.warmth ?? 0, -1, 0.001)
        expect(LightStats.from(rgba: []) == nil, "no pixels, no light")
    }
    test("Sun picks: the darkest wallpaper goes to night, the brightest to day") {
        let p = SunPicker.pick([noon, grey, starfield])
        expectEqual(p.night, "stars"); expectEqual(p.day, "noon")
    }
    test("Sun picks: warm, middle-bright wallpapers become dusk (warmest) and dawn") {
        let p = SunPicker.pick([rose, starfield, ember, noon])
        expectEqual(p.dusk, "ember"); expectEqual(p.dawn, "rose")
        expectEqual(p.night, "stars"); expectEqual(p.day, "noon")
    }
    test("Sun picks: a soft pink sky goes to dawn, an orange one to dusk, and a lone warm picture to dusk") {
        func px(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> [UInt8] { Array(repeating: [r, g, b, 255], count: 16).flatMap { $0 } }
        let pink = SunCandidate(id: "pink", title: "Lagoon", light: LightStats.from(rgba: px(160, 100, 132))!)
        let orange = SunCandidate(id: "orange", title: "Ember", light: LightStats.from(rgba: px(196, 92, 52))!)
        let p = SunPicker.pick([pink, orange, starfield, noon])
        expectEqual(p.dawn, "pink"); expectEqual(p.dusk, "orange")
        let lone = SunPicker.pick([orange, starfield, noon])
        expectEqual(lone.dusk, "orange"); expectEqual(lone.dawn, nil)
    }
    test("Sun picks: words in the title beat a close call on colour") {
        let rise = c("rise", "Sunrise over the bay", luma: 0.4, warmth: 0.3)
        let set = c("set", "Sunset pier", luma: 0.4, warmth: 0.25)
        let p = SunPicker.pick([set, rise, starfield, noon])
        expectEqual(p.dawn, "rise"); expectEqual(p.dusk, "set")
        let moon = c("moon", "Moonlit city at night", luma: 0.2, warmth: 0.1)
        expectEqual(SunPicker.pick([moon, c("cave", "Cave", luma: 0.12, warmth: 0), noon]).night, "moon")
    }
    test("Sun picks: nothing warm means no dawn or dusk (Day/Night alone)") {
        let p = SunPicker.pick([starfield, noon, grey])
        expectEqual(p.dawn, nil); expectEqual(p.dusk, nil)
        expect(p.day != nil && p.night != nil)
    }
    test("Sun picks: each wallpaper is used once, whatever the input order") {
        let all = [rose, starfield, ember, noon, grey]
        let a = SunPicker.pick(all), b = SunPicker.pick(all.reversed())
        expectEqual(a, b)
        let ids = [a.dawn, a.day, a.dusk, a.night].compactMap { $0 }
        expectEqual(Set(ids).count, ids.count, "no wallpaper twice")
    }
    test("Sun picks: today's start of dawn, day, dusk and night (fixed times 07:00 to 19:00)") {
        let utc = TimeZone(identifier: "UTC")!
        let s = DayNightSchedule(mode: .manual(dayStartMinute: 7 * 60, nightStartMinute: 19 * 60), timeZone: utc)
        let midnight = 1_795_000_000 - 1_795_000_000 % 86_400   // a UTC midnight
        let noon = Date(timeIntervalSince1970: TimeInterval(midnight + 12 * 3600))
        let starts = s.partStarts(onLocalDayOf: noon)
        let day0 = noon.addingTimeInterval(-12 * 3600)
        func hour(_ p: DayPart) -> Double? { starts[p].map { $0.timeIntervalSince(day0) / 3600 } }
        expectEqual(hour(.dawn), 7); expectEqual(hour(.day), 8); expectEqual(hour(.dusk), 18); expectEqual(hour(.night), 19)
    }
    test("Sun picks: with real sun times the four parts come in order (Bangkok)") {
        let bkk = TimeZone(identifier: "Asia/Bangkok")!
        let s = DayNightSchedule(mode: .sun(latitude: 13.75, longitude: 100.5), timeZone: bkk)
        let starts = s.partStarts(onLocalDayOf: Date(timeIntervalSince1970: 1_795_000_000))
        guard let a = starts[.dawn], let b = starts[.day], let c = starts[.dusk], let d = starts[.night] else {
            expect(false, "all four parts happen in Bangkok: \(starts)"); return
        }
        expect(a < b && b < c && c < d, "dawn < day < dusk < night: \(starts)")
        expect(b.timeIntervalSince(a) > 15 * 60 && b.timeIntervalSince(a) < 90 * 60, "dawn lasts tens of minutes")
    }
    test("Sun picks: fewer than two wallpapers picks nothing") {
        expectEqual(SunPicker.pick([]), SunPicks())
        expectEqual(SunPicker.pick([noon]), SunPicks())
        expectEqual(SunPicker.pick([noon, noon]), SunPicks(), "the same wallpaper twice is still one")
    }
}
