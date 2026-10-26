// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Smart pausing: why playback pauses, the status line, the CPU gate and releasing players after a long pause.
import Foundation

func registerPauseTests() {
    let prefs = PausePrefs(pauseOnBattery: false, batteryBelowPercent: 20, pauseLowPower: true,
                           thermalLimit: .serious, cpuAbovePercent: 0, pauseWhenCovered: true)

    test("Pause: nothing to pause for means playing") {
        expectEqual(PausePolicy.reason(PowerSnapshot(), prefs), nil)
    }
    test("Pause: user pause wins over every other reason") {
        var s = PowerSnapshot(); s.userPaused = true; s.locked = true; s.lowPower = true
        expectEqual(PausePolicy.reason(s, prefs), .user)
    }
    test("Pause: locked, then display asleep, in that order") {
        var s = PowerSnapshot(); s.locked = true; s.asleep = true
        expectEqual(PausePolicy.reason(s, prefs), .locked)
        s.locked = false
        expectEqual(PausePolicy.reason(s, prefs), .asleep)
    }
    test("Pause: on battery only when that setting is on (existing 1.2.0 behaviour)") {
        var s = PowerSnapshot(); s.onBattery = true; s.batteryPercent = 80
        expectEqual(PausePolicy.reason(s, prefs), nil)
        var p = prefs; p.pauseOnBattery = true
        expectEqual(PausePolicy.reason(s, p), .onBattery)
    }
    test("Pause: battery below the threshold, only while on battery") {
        var s = PowerSnapshot(); s.onBattery = true; s.batteryPercent = 19
        expectEqual(PausePolicy.reason(s, prefs), .batteryLow)
        s.batteryPercent = 20
        expectEqual(PausePolicy.reason(s, prefs), nil, "20% is not below 20%")
        s.batteryPercent = 5; s.onBattery = false
        expectEqual(PausePolicy.reason(s, prefs), nil, "charging at 5% keeps playing")
        s.onBattery = true; s.batteryPercent = nil
        expectEqual(PausePolicy.reason(s, prefs), nil, "unknown charge never pauses")
        var off = prefs; off.batteryBelowPercent = 0; s.batteryPercent = 3
        expectEqual(PausePolicy.reason(s, off), nil, "0 turns the threshold off")
    }
    test("Pause: Low Power Mode follows its setting") {
        var s = PowerSnapshot(); s.lowPower = true
        expectEqual(PausePolicy.reason(s, prefs), .lowPower)
        var p = prefs; p.pauseLowPower = false
        expectEqual(PausePolicy.reason(s, p), nil)
    }
    test("Pause: thermal pressure at or above the limit") {
        var s = PowerSnapshot(); s.thermal = .fair
        expectEqual(PausePolicy.reason(s, prefs), nil)
        s.thermal = .serious
        expectEqual(PausePolicy.reason(s, prefs), .thermal)
        s.thermal = .critical
        expectEqual(PausePolicy.reason(s, prefs), .thermal)
        var p = prefs; p.thermalLimit = nil
        expectEqual(PausePolicy.reason(s, p), nil, "no limit = never pause for heat")
    }
    test("Pause: busy CPU only when the gate is tripped and the setting is on") {
        var s = PowerSnapshot(); s.cpuBusy = true
        expectEqual(PausePolicy.reason(s, prefs), nil, "cpuAbovePercent 0 = off")
        var p = prefs; p.cpuAbovePercent = 80
        expectEqual(PausePolicy.reason(s, p), .cpuBusy)
    }
    test("Pause: every reason has a short human label") {
        for r in PauseReason.allCases { expect(!r.label.isEmpty && r.label.count < 40, "\(r)") }
        expectEqual(PauseReason.covered.label, "full-screen app")
    }

    test("Status: playing, paused with a reason, covered, nothing set") {
        expectEqual(PlaybackStatus.text(global: nil, displays: [.playing]), "Playing")
        expectEqual(PlaybackStatus.text(global: .lowPower, displays: [.playing]), "Paused: Low Power Mode")
        expectEqual(PlaybackStatus.text(global: nil, displays: [.covered]), "Paused: full-screen app")
        expectEqual(PlaybackStatus.text(global: nil, displays: [.playing, .covered]), "Playing (1 of 2 displays paused: full-screen app)")
        expectEqual(PlaybackStatus.text(global: nil, displays: []), "No wallpaper playing")
        expectEqual(PlaybackStatus.text(global: .user, displays: []), "Paused: by you")
    }

    test("CPU: busy fraction from tick deltas, robust to counter wrap and no change") {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let b = CPUTicks(user: 160, system: 70, idle: 870, nice: 0)
        expectNear(CPUTicks.busyFraction(from: a, to: b) ?? -1, 0.8, 0.0001)
        expectEqual(CPUTicks.busyFraction(from: a, to: a), nil, "no ticks elapsed")
        expectEqual(CPUTicks.busyFraction(from: b, to: a), nil, "counters went backwards (wrap/reset)")
    }
    test("CPU gate: trips on a sustained average, not a spike, with hysteresis") {
        var g = CPUGate(thresholdPercent: 80, window: 3)
        expect(!g.feed(0.99), "one spike does not pause")
        expect(!g.feed(0.5))
        expect(!g.feed(0.9), "average (0.99+0.5+0.9)/3 = 0.797 < 0.8")
        expect(!g.feed(0.95), "average (0.5+0.9+0.95)/3 = 0.783 < 0.8")
        expect(g.feed(0.99), "average (0.9+0.95+0.99)/3 > 0.8")
        expect(g.feed(0.75), "stays tripped until the average drops 10 points below")
        expect(g.feed(0.7))
        expect(!g.feed(0.6), "average (0.75+0.7+0.6)/3 = 0.683 < 0.7, releases")
        var off = CPUGate(thresholdPercent: 0, window: 3)
        expect(!off.feed(1) && !off.feed(1) && !off.feed(1), "0 = never trips")
    }

    test("Idle release: only after a long, continuous global pause") {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        expect(!IdleRelease.shouldRelease(pausedSince: nil, now: t0, afterMinutes: 5))
        expect(!IdleRelease.shouldRelease(pausedSince: t0, now: t0.addingTimeInterval(299), afterMinutes: 5))
        expect(IdleRelease.shouldRelease(pausedSince: t0, now: t0.addingTimeInterval(300), afterMinutes: 5))
        expect(!IdleRelease.shouldRelease(pausedSince: t0, now: t0.addingTimeInterval(9999), afterMinutes: 0), "0 = never release")
        expect(!IdleRelease.shouldRelease(pausedSince: t0, now: t0.addingTimeInterval(-60), afterMinutes: 5), "clock moved back")
    }
}
