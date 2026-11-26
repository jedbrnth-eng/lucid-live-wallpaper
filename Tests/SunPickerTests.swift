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
    test("Sun picks: fewer than two wallpapers picks nothing") {
        expectEqual(SunPicker.pick([]), SunPicks())
        expectEqual(SunPicker.pick([noon]), SunPicks())
        expectEqual(SunPicker.pick([noon, noon]), SunPicks(), "the same wallpaper twice is still one")
    }
}
