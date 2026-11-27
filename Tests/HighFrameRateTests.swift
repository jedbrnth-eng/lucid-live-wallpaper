// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// "Half speed for 240 fps videos" (Settings, off by default): which videos it slows, and by how much.
import Foundation

func registerHighFrameRateTests() {
    func spin(_ limit: Double, until done: () -> Bool) {
        let end = Date().addingTimeInterval(limit)
        while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    test("Half speed for 240 fps: off (the default) changes nothing") {
        expectEqual(HighFrameRate.speed(options: nil, defaultSpeed: 1, fps: 240, halfSpeedOn: false), 1)
    }
    test("Half speed for 240 fps: on, a 240 fps video plays at half the speed it would have") {
        expectEqual(HighFrameRate.speed(options: nil, defaultSpeed: 1, fps: 240, halfSpeedOn: true), 0.5)
        expectEqual(HighFrameRate.speed(options: nil, defaultSpeed: 1, fps: 239.76, halfSpeedOn: true), 0.5)
        expectEqual(HighFrameRate.speed(options: nil, defaultSpeed: 1.5, fps: 240, halfSpeedOn: true), 0.75, "half of the app-wide speed")
    }
    test("Half speed for 240 fps: 24 to 120 fps videos and unknown rates keep their speed") {
        for f in [24.0, 30, 60, 120] { expectEqual(HighFrameRate.speed(options: nil, defaultSpeed: 1, fps: f, halfSpeedOn: true), 1, "\(f) fps") }
        expectEqual(HighFrameRate.speed(options: nil, defaultSpeed: 1, fps: nil, halfSpeedOn: true), 1)
    }
    test("Half speed for 240 fps: a speed you set on the wallpaper wins") {
        var o = WallpaperOptions(); o.speed = 1
        expectEqual(HighFrameRate.speed(options: o, defaultSpeed: 1, fps: 240, halfSpeedOn: true), 1)
        o.speed = 0.25
        expectEqual(HighFrameRate.speed(options: o, defaultSpeed: 1, fps: 240, halfSpeedOn: true), 0.25)
    }
    test("Frame rates: read from the file once (the 30 fps test clip); 0 when it can't be read") {
        guard let v = TestVideo.path else { expect(false, "no test video"); return }
        MainActor.assumeIsolated {
            var calls = 0
            FrameRates.load(v) { calls += 1 }
            FrameRates.load(v) { calls += 1 }   // asked twice while reading: read once, both told
            spin(5) { calls == 2 }
            expectEqual(calls, 2)
            expectNear(FrameRates.fps(v) ?? 0, 30, 0.5)
            let bad = FileManager.default.temporaryDirectory.appendingPathComponent("lucid-test-bad-\(getpid()).mov")
            try? Data("not a video".utf8).write(to: bad)
            defer { try? FileManager.default.removeItem(at: bad) }
            var done = false
            FrameRates.load(bad.path) { done = true }
            spin(5) { done }
            expectEqual(FrameRates.fps(bad.path), 0, "unreadable: 0, so the video plays at its normal speed")
        }
    }
}
