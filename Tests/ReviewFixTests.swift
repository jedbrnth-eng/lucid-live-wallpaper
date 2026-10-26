// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Regression tests for the 1.3.0 security/robustness review: malformed saved data, hostile update responses,
// header/extension mismatches, and the file-deletion and import rules used by the library.
import Foundation

func registerReviewFixTests() {
    // H3: the release page link must really be our repo's release page, after normalisation.
    test("Review H3: update links with .. segments, user info, a port, encoded dots or a query are refused") {
        let good = "https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/tag/v9.0.0"
        func parse(_ page: String) -> ReleaseInfo? {
            UpdateCheck.parse(Data(#"{"tag_name":"v9.0.0","html_url":"\#(page)","draft":false,"prerelease":false}"#.utf8))
        }
        expectEqual(parse(good)?.version, "9.0.0")
        for bad in ["https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/../../../attacker/malware",
                    "https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/tag/../../../../attacker/x",
                    "https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/%2e%2e/%2e%2e/%2e%2e/attacker",
                    "https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/./tag/v9.0.0",
                    "https://evil@github.com/jedbrnth-eng/lucid-live-wallpaper/releases/tag/v9.0.0",
                    "https://github.com:8443/jedbrnth-eng/lucid-live-wallpaper/releases/tag/v9.0.0",
                    "https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/tag/v9.0.0?x=1",
                    "https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/download/v9.0.0/Lucid.zip"] {
            expectEqual(parse(bad), nil, bad)
        }
    }

    // M1: one JSON null in a saved list must not lose the whole list.
    test("Review M1: a null entry in library/playlists is skipped, the rest is kept") {
        let one = #"{"id":"local:a","source":"local","kind":"image","title":"A","width":1,"height":1}"#
        expectEqual(SavedData.items(Data("[null,\(one)]".utf8)).map(\.id), ["local:a"])
        expectEqual(SavedData.items(Data("[\(one),null,\(one.replacingOccurrences(of: "local:a", with: "local:b"))]".utf8)).map(\.id), ["local:a", "local:b"])
        let pl = #"{"id":"p","name":"P","items":[null],"shuffle":true,"minutes":60}"#
        expectEqual(SavedData.playlists(Data("[null,\(pl)]".utf8)).map(\.id), ["p"])
    }

    // M2: zone.tab coordinates with non-ASCII digits must be refused, not crash.
    test("Review M2: ISO 6709 with non-ASCII digits is refused without crashing") {
        expectEqual(TimeZoneCoordinates.parseISO6709("+1345²+10030").map { [$0.0, $0.1] }, nil)
        expectEqual(TimeZoneCoordinates.parseISO6709("+１３４５+１００３０").map { [$0.0, $0.1] }, nil)
        expectEqual(TimeZoneCoordinates.parseISO6709("+1345+10031").map { [($0.0 * 100).rounded(), ($0.1 * 100).rounded()] }, [1375, 10052])
    }
    test("Review M2: the analyser survives absurd sample rates and FFT sizes") {
        for sr in [1e-300, Double.infinity, -1, 0, Double.nan, 1e12] {
            let a = AudioAnalyser(sampleRate: sr)
            expect(a.sampleRate >= 8_000 && a.sampleRate <= 768_000, "sampleRate \(sr) -> \(a.sampleRate)")
        }
        expect(AudioAnalyser(sampleRate: 48_000, fftSize: Int.max).fftSize <= 16_384)
        expect(AudioAnalyser(sampleRate: 48_000, fftSize: -5).fftSize >= 64)
    }

    // M3: damaged playback.json and out-of-range manual times.
    test("Review M3: a saved playlist position out of range is repaired, never overflows") {
        for pos in ["9223372036854775807", "-3", "99"] {
            let j = #"{"runs":{"*":{"playlistID":"p","order":["a","b","c"],"position":\#(pos),"changedAt":0}}}"#
            guard var r = PlaybackState.decode(Data(j.utf8)).runs["*"] else { expect(false, "run dropped for \(pos)"); continue }
            expect(r.current != nil, "position \(pos) leaves nothing to show")
            var g = SystemRandomNumberGenerator()
            r.advance(ids: ["a", "b", "c"], shuffle: false, now: Date(), rng: &g)
            expect(r.current != nil, "after advance, position \(pos)")
        }
    }
    test("Review M3: manual day/night minutes outside 0..<1440 behave like the same time of day") {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let day0 = cal.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let ref = DayNightSchedule(mode: .manual(dayStartMinute: 420, nightStartMinute: 1140), timeZone: cal.timeZone)
        for (ds, ns) in [(420 + 1440 * 3, 1140 - 1440 * 2), (420 - 1440, 1140 + 1440), (420 - 1440 * 5, 1140)] {
            let s = DayNightSchedule(mode: .manual(dayStartMinute: ds, nightStartMinute: ns), timeZone: cal.timeZone)
            for m in stride(from: 0, to: 1440, by: 15) {
                let t = day0.addingTimeInterval(Double(m) * 60)
                expectEqual(s.phase(at: t), ref.phase(at: t), "phase \(ds),\(ns) at \(m)")
                expectEqual(s.part(at: t), ref.part(at: t), "part \(ds),\(ns) at \(m)")
                expectEqual(s.nextChange(after: t), ref.nextChange(after: t), "nextChange \(ds),\(ns) at \(m)")
                expectEqual(s.nextBoundary(after: t), ref.nextBoundary(after: t), "nextBoundary \(ds),\(ns) at \(m)")
            }
        }
    }
    test("Review M3: huge or non-finite per-wallpaper numbers never reach the layer") {
        let o = SavedData.items(Data(#"[{"id":"local:x","source":"local","kind":"video","title":"X","width":1,"height":1,"options":{"speed":1e999,"focusX":-1e999}}]"#.utf8)).first?.options
        let sp = (o ?? WallpaperOptions()).effectiveSpeed(default: 1)
        expect(sp.isFinite && sp >= 0.25 && sp <= 4, "speed \(sp)")
        let f = FillLayout.frame(media: (w: 100, h: 100), bounds: (w: 1000, h: 500), mode: .fill, focusX: .nan, focusY: .infinity)
        expect([f.x, f.y, f.w, f.h].allSatisfy(\.isFinite), "\(f)")
        let s2 = WallpaperOptions(speed: .nan).effectiveSpeed(default: 1)
        expect(s2.isFinite, "nan speed -> \(s2)")
    }
    test("Review M2: Day/Night survives extreme dates without crashing") {
        let s = DayNightSchedule(mode: .sun(latitude: 13.75, longitude: 100.5), timeZone: TimeZone(identifier: "Asia/Bangkok")!)
        for t in [Date.distantFuture, Date.distantPast, Date(timeIntervalSinceReferenceDate: 1e15)] {
            _ = s.phase(at: t); _ = s.part(at: t); _ = s.nextChange(after: t); _ = s.nextBoundary(after: t)
        }
        expect(true)
    }

    // L2: the header must match the kind the extension claims.
    test("Review L2: contents must match the extension's kind; loose BMP headers are refused") {
        let mp4 = [0, 0, 0, 0x18] + Array("ftypmp42".utf8) + [0, 0, 0, 0]
        let bmp: [UInt8] = Array("BM".utf8) + [0x36, 0x10, 0x0E, 0, 0, 0, 0, 0, 0x36, 0, 0, 0, 0x28, 0]
        let looseBM: [UInt8] = Array("BM is my favourite".utf8)
        let heicSeq = [0, 0, 0, 0x18] + Array("ftyphevc".utf8) + [0, 0, 0, 0]
        expectEqual(ImportPolicy.check(ext: "mp4", size: 900, header: bmp), .rejected("the contents are not a video or photo"), "photo bytes named .mp4")
        expectEqual(ImportPolicy.check(ext: "png", size: 900, header: mp4), .rejected("the contents are not a video or photo"), "video bytes named .png")
        expectEqual(ImportPolicy.check(ext: "bmp", size: 900, header: bmp), .ok(.image))
        expectEqual(ImportPolicy.sniff(looseBM), .unknown, "any text starting with BM")
        expectEqual(ImportPolicy.check(ext: "heic", size: 900, header: heicSeq), .ok(.image), "HEIC image sequences stay accepted")
        expectEqual(ImportPolicy.check(ext: "jpg", size: 900, header: Array("GIF89a".utf8) + [UInt8](repeating: 0, count: 10)), .ok(.image), "a GIF named .jpg is still a photo")
        expectEqual(ImportPolicy.check(ext: "gif", size: 900, header: Array("GIF89a".utf8) + [UInt8](repeating: 0, count: 10)), .ok(.image), "GIF starts with 0x47 but is not MPEG-TS")
    }
}
