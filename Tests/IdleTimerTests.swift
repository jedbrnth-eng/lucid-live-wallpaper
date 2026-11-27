// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Lucid while nothing needs it: no timer runs for a feature that is off, and folders are watched, not scanned.
import Foundation

func registerIdleTimerTests() {
    func spin(_ limit: Double, until done: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(limit)
        while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
    test("Timers: a periodic job whose feature is off has no timer and never runs") {
        MainActor.assumeIsolated {
            var runs = 0
            let p = Periodic(every: 0.05) { runs += 1 }
            expect(!p.isRunning, "made off")
            spin(0.25)
            expectEqual(runs, 0, "off: never runs")
            p.set(true); p.set(true)
            expect(p.isRunning)
            spin(0.4)
            expect(runs >= 2 && runs <= 9, "\(runs) runs in 0.4 s every 0.05 s (one timer, however often it is switched on)")
            p.set(false)
            let n = runs
            spin(0.25)
            expect(!p.isRunning); expectEqual(runs, n, "switched off: stops")
        }
    }
    test("Timers: the long-pause release is one wake-up at its deadline (no check every 20 s)") {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        expectEqual(IdleRelease.deadline(pausedSince: t0, afterMinutes: 5), t0.addingTimeInterval(300))
        expectEqual(IdleRelease.deadline(pausedSince: nil, afterMinutes: 5), nil, "not paused: no timer")
        expectEqual(IdleRelease.deadline(pausedSince: t0, afterMinutes: 0), nil, "0 = never release: no timer")
        if let d = IdleRelease.deadline(pausedSince: t0, afterMinutes: 5) {
            expect(IdleRelease.shouldRelease(pausedSince: t0, now: d, afterMinutes: 5), "due at the deadline")
        }
    }
    test("Folder watch: a file dropped into a watched folder is noticed at once (no 5 s scan)") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lucid-watch-\(getpid())", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var calls = 0
        let w = DirectoryWatcher([dir], debounce: 0.05) { calls += 1 }
        spin(0.2)
        expectEqual(calls, 0, "nothing changed: nothing runs")
        FileManager.default.createFile(atPath: dir.appendingPathComponent("drop.mov").path, contents: Data([0]))
        spin(1.5) { calls > 0 }
        expectEqual(calls, 1, "one look for the drop")
        try? FileManager.default.moveItem(at: dir.appendingPathComponent("drop.mov"), to: dir.appendingPathComponent("renamed.mov"))
        spin(1.5) { calls > 1 }
        expectEqual(calls, 2, "and one for a rename inside the folder")
        withExtendedLifetime(w) {}
    }
    test("Folder watch: a file still being written is looked at again once it can have settled") {
        let now = Date(timeIntervalSince1970: 2_000_000)
        expectEqual(ImportPolicy.recheckDelay(modified: [], now: now), nil, "nothing waiting: no timer")
        expectEqual(ImportPolicy.recheckDelay(modified: [now.addingTimeInterval(-4), now.addingTimeInterval(-10)], now: now), 5.5,
                    "the first to settle (10 s old) settles in 5 s; look just after")
        expectEqual(ImportPolicy.recheckDelay(modified: [now.addingTimeInterval(3600)], now: now), 15.5, "a date in the future: one look per 15 s at most")
        expect(ImportPolicy.isSettled(modified: now.addingTimeInterval(-15), now: now))
        expect(!ImportPolicy.isSettled(modified: now.addingTimeInterval(-14), now: now))
    }
}
