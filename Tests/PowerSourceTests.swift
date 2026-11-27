// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Reading macOS's power-source list: on battery or not, and which charge counts.
import Foundation

func registerPowerSourceTests() {
    func source(_ cur: Int, _ max: Int, _ type: String = "InternalBattery") -> [String: Any] {
        ["Current Capacity": cur, "Max Capacity": max, "Type": type]
    }
    test("Power: on AC with a full battery") {
        let r = PowerSources.reading(providing: "AC Power", sources: [source(100, 100)])
        expect(!r.onBattery); expectEqual(r.percent, 100)
    }
    test("Power: on battery, charge as a rounded percent") {
        let r = PowerSources.reading(providing: "Battery Power", sources: [source(45, 100)])
        expect(r.onBattery); expectEqual(r.percent, 45)
        expectEqual(PowerSources.reading(providing: "Battery Power", sources: [source(2, 3)]).percent, 67)
    }
    test("Power: the Mac's own battery counts, not a UPS listed after it") {
        let r = PowerSources.reading(providing: "Battery Power", sources: [source(80, 100), source(20, 100, "UPS")])
        expectEqual(r.percent, 80, "a nearly empty UPS must not make Lucid pause for low battery")
    }
    test("Power: a desktop Mac running from its UPS is on battery, with the UPS charge") {
        let r = PowerSources.reading(providing: "UPS Power", sources: [source(30, 100, "UPS")])
        expect(r.onBattery, "IOPSGetProvidingPowerSourceType says UPS Power during a power cut")
        expectEqual(r.percent, 30)
    }
    test("Power: the Mac's own battery counts even when a UPS is listed first") {
        expectEqual(PowerSources.reading(providing: "Battery Power", sources: [source(20, 100, "UPS"), source(80, 100)]).percent, 80)
    }
    test("Power: no readable battery means unknown charge (never pauses for low battery)") {
        expectEqual(PowerSources.reading(providing: "AC Power", sources: []).percent, nil)
        expectEqual(PowerSources.reading(providing: "Battery Power", sources: [source(10, 0)]).percent, nil)
        expectEqual(PowerSources.reading(providing: nil, sources: []).onBattery, false)
    }

    // The monitor, with a plain run-loop source standing in for the IOPS one (same callback, same context).
    func testSource(_ ctx: UnsafeMutableRawPointer) -> CFRunLoopSource? {
        var c = CFRunLoopSourceContext(version: 0, info: ctx, retain: nil, release: nil, copyDescription: nil,
                                       equal: nil, hash: nil, schedule: nil, cancel: nil, perform: PowerMonitor.callback)
        return CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &c)
    }
    func fire(_ s: CFRunLoopSource) {
        CFRunLoopSourceSignal(s); CFRunLoopWakeUp(CFRunLoopGetMain())
        _ = CFRunLoopRunInMode(.defaultMode, 0.05, true)
    }
    test("Power monitor: a pushed change is read and delivered once") {
        var now = PowerReading(onBattery: false, percent: 100), got: [PowerReading] = []
        let m = PowerMonitor(read: { now }, wakeCenter: NotificationCenter(), wakeNames: [], makeSource: testSource) { got.append($0) }
        expectEqual(got, [now], "the first reading arrives at once")
        now = PowerReading(onBattery: true, percent: 99)
        if let s = m.source { fire(s); fire(s) }
        expectEqual(got.count, 2, "one delivery per change, \(got)")
        expectEqual(got.last, now)
    }
    test("Power monitor: waking re-reads the power source (a plug or unplug while asleep sends no event)") {
        let center = NotificationCenter(), wake = Notification.Name("test.didWake")
        var now = PowerReading(onBattery: false, percent: 100), got: [PowerReading] = []
        let m = PowerMonitor(read: { now }, wakeCenter: center, wakeNames: [wake], makeSource: testSource) { got.append($0) }
        now = PowerReading(onBattery: true, percent: 64)
        center.post(name: wake, object: nil)
        expectEqual(got.last, now, "unplugged during sleep: on battery after wake")
        withExtendedLifetime(m) {}
    }
    test("Power monitor: changes arrive in every common run-loop mode (also while a menu or slider tracks)") {
        let m = PowerMonitor(read: { nil }, wakeCenter: NotificationCenter(), wakeNames: [], makeSource: testSource) { _ in }
        guard let s = m.source else { expect(false, "no source"); return }
        expect(CFRunLoopContainsSource(CFRunLoopGetMain(), s, .commonModes), "scheduled in the common modes")
    }
    test("Power monitor: releasing it invalidates its source, so no callback can reach freed memory") {
        var m: PowerMonitor? = PowerMonitor(read: { nil }, wakeCenter: NotificationCenter(), wakeNames: [], makeSource: testSource) { _ in }
        guard let s = m?.source else { expect(false, "no source"); return }
        weak var gone = m
        m = nil
        expect(gone == nil, "the monitor itself is freed")
        expect(!CFRunLoopSourceIsValid(s), "its run-loop source is invalidated")
        expect(!CFRunLoopContainsSource(CFRunLoopGetMain(), s, .commonModes) && !CFRunLoopContainsSource(CFRunLoopGetMain(), s, .defaultMode))
    }
}
