// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// A repeating job that runs only while it is wanted, so a feature that is off costs no wakeups at all.
// `set(true)` starts the timer (first run one interval later) and `set(false)` stops it; both can be called as often
// as convenient. macOS may move each run by a tenth of the interval to batch it with other wakeups. Foundation only.
import Foundation

@MainActor final class Periodic {
    let interval: TimeInterval
    private let job: () -> Void
    nonisolated(unsafe) private var timer: Timer?
    var isRunning: Bool { timer != nil }

    init(every interval: TimeInterval, _ job: @escaping () -> Void) {
        self.interval = interval
        self.job = job
    }

    deinit { timer?.invalidate() }

    func set(_ wanted: Bool) {
        if wanted, timer == nil {
            let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.job() }
            }
            t.tolerance = interval / 10
            timer = t
        } else if !wanted, let t = timer {
            t.invalidate()
            timer = nil
        }
    }
}
