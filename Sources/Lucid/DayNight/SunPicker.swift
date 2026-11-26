// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// "Pick for me" in Day & Night: which wallpaper suits dawn, day, dusk and night, judged by the light in each
// picture (how bright, how warm, how colourful) with words in its title as a tie-breaker. The darkest goes to
// night, the brightest to day, warm middle-bright ones to dusk (orange, the warmest) and dawn (softer, pinker).
// Dawn and dusk stay empty when nothing looks like them, which leaves plain Day/Night. Pure, so it is unit-tested.
import Foundation

/// The light in a picture, from its average colour.
struct LightStats: Equatable, Codable {
    var luma: Double         // 0 black … 1 white (Rec. 709 weights)
    var warmth: Double       // -1 blue … +1 orange (red minus blue)
    var saturation: Double   // 0 grey … 1 vivid
    /// Average colour (red, green, blue in 0…1) for drawing; empty when made from numbers alone.
    var rgb: [Double] = []

    /// From RGBA bytes, any number of pixels (alpha ignored).
    static func from(rgba: [UInt8]) -> LightStats? {
        let n = rgba.count / 4
        guard n > 0 else { return nil }
        var r = 0.0, g = 0.0, b = 0.0, sat = 0.0
        for i in 0..<n {
            let R = Double(rgba[i * 4]) / 255, G = Double(rgba[i * 4 + 1]) / 255, B = Double(rgba[i * 4 + 2]) / 255
            r += R; g += G; b += B
            let hi = max(R, G, B), lo = min(R, G, B)
            sat += hi > 0 ? (hi - lo) / hi : 0
        }
        let k = Double(n)
        r /= k; g /= k; b /= k
        return LightStats(luma: 0.2126 * r + 0.7152 * g + 0.0722 * b, warmth: r - b, saturation: sat / k, rgb: [r, g, b])
    }
}

struct SunCandidate: Equatable {
    var id: String
    var title: String
    var light: LightStats
}

struct SunPicks: Equatable {
    var dawn: String?
    var day: String?
    var dusk: String?
    var night: String?
}

enum SunPicker {
    static let words: [DayPart: [String]] = [
        .dawn: ["sunrise", "dawn", "morning", "daybreak", "first light"],
        .dusk: ["sunset", "dusk", "evening", "golden hour", "twilight"],
        .night: ["night", "star", "milky way", "galaxy", "nebula", "aurora", "moon", "space", "neon", "city lights"],
        .day: ["noon", "beach", "ocean", "sky", "cloud", "forest", "meadow", "snow", "mountain", "lake"],
    ]
    /// What leaving dawn or dusk empty is worth: a pick has to beat it.
    static let emptyScore = 0.9

    static func hasWord(_ title: String, _ part: DayPart) -> Bool {
        let t = title.lowercased()
        return (words[part] ?? []).contains { t.contains($0) }
    }

    static func score(_ c: SunCandidate, _ part: DayPart) -> Double {
        let l = c.light, named = hasWord(c.title, part) ? 1.0 : 0
        let middle = max(0, 1 - abs(l.luma - 0.4) * 2.5)   // 1 at 40% brightness, 0 at black or 80%
        // Pink skies carry more blue than green; orange ones more green than blue (needs the average colour).
        let tilt = l.rgb.count == 3 ? l.rgb[2] - l.rgb[1] : 0
        switch part {
        case .night: return (1 - l.luma) * 2 + max(0, -l.warmth) * 0.5 + named * 1.2
        case .day: return l.luma * 2 + l.saturation * 0.3 - abs(l.warmth) * 0.5 + named * 0.6
        case .dusk: return max(0, l.warmth) * 3 + middle + max(0, -tilt) + named * 1.5
        case .dawn: return max(0, l.warmth) * 2 + middle + max(0, tilt) * 3 + named * 1.5
        }
    }

    /// Dawn and dusk only take a wallpaper that is named like one, or neither black nor washed out and warm
    /// (dusk), or warm or rosy (dawn: mauve and pink skies carry nearly as much blue as red).
    static func qualifies(_ c: SunCandidate, _ part: DayPart) -> Bool {
        let l = c.light, lit = l.luma >= 0.12 && l.luma <= 0.75
        let rosy = l.rgb.count == 3 && l.rgb[0] - l.rgb[1] >= 0.1 && l.rgb[2] - l.rgb[1] >= 0.05
        switch part {
        case .day, .night: return true
        case .dusk: return hasWord(c.title, part) || (lit && l.warmth >= 0.05)
        case .dawn: return hasWord(c.title, part) || (lit && (l.warmth >= 0.05 || rosy))
        }
    }

    /// The best set of distinct wallpapers (highest total score). Needs two different wallpapers; fewer picks nothing.
    static func pick(_ candidates: [SunCandidate]) -> SunPicks {
        var seen = Set<String>()
        let cs = candidates.sorted { $0.id < $1.id }.filter { seen.insert($0.id).inserted }
        guard cs.count >= 2 else { return SunPicks() }
        // The best choice for a part is always among its top four (the other three parts use at most three).
        func top(_ p: DayPart) -> [SunCandidate] {
            Array(cs.filter { qualifies($0, p) }
                .sorted { score($0, p) != score($1, p) ? score($0, p) > score($1, p) : $0.id < $1.id }
                .prefix(5))
        }
        let nights = top(.night), days = top(.day)
        let dusks: [SunCandidate?] = [nil] + top(.dusk), dawns: [SunCandidate?] = [nil] + top(.dawn)
        var best: (total: Double, picks: SunPicks)?
        for n in nights {
            for d in days where d.id != n.id {
                for k in dusks where k == nil || (k!.id != n.id && k!.id != d.id) {
                    for w in dawns where w == nil || (w!.id != n.id && w!.id != d.id && w!.id != k?.id) {
                        let total = score(n, .night) + score(d, .day)
                            + (k.map { score($0, .dusk) } ?? emptyScore) + (w.map { score($0, .dawn) } ?? emptyScore)
                        if best == nil || total > best!.total + 1e-9 {
                            best = (total, SunPicks(dawn: w?.id, day: d.id, dusk: k?.id, night: n.id))
                        }
                    }
                }
            }
        }
        return best?.picks ?? SunPicks()
    }
}
