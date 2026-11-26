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
    test("Power: no readable battery means unknown charge (never pauses for low battery)") {
        expectEqual(PowerSources.reading(providing: "AC Power", sources: []).percent, nil)
        expectEqual(PowerSources.reading(providing: "Battery Power", sources: [source(10, 0)]).percent, nil)
        expectEqual(PowerSources.reading(providing: nil, sources: []).onBattery, false)
    }
}
