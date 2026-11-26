// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// The process meter behind the headless playback benchmark.
import Foundation

func registerBenchTests() {
    test("Meter: rates between two samples (CPU %, mW, MB, wakeups/s)") {
        let a = ProcessSample(cpuNanos: 1_000_000_000, energyNanojoules: 5_000_000_000, footprintBytes: 50 * 1_048_576, wakeups: 100, at: 100)
        let b = ProcessSample(cpuNanos: 1_500_000_000, energyNanojoules: 6_000_000_000, footprintBytes: 100 * 1_048_576, wakeups: 300, at: 110)
        let r = ProcessMeter.rates(from: a, to: b)
        expectEqual(r.cpuPercent, 5, "0.5 s of CPU in 10 s")
        expectEqual(r.energyMilliwatts, 100, "1 J in 10 s")
        expectEqual(r.footprintMB, 100, "the later sample's footprint")
        expectEqual(r.wakeupsPerSecond, 20)
    }
    test("Meter: no elapsed time or counters going backwards give 0, never a crash") {
        let a = ProcessSample(cpuNanos: 9, energyNanojoules: 9, footprintBytes: 0, wakeups: 9, at: 5)
        let same = ProcessMeter.rates(from: a, to: a)
        expectEqual(same.cpuPercent, 0); expectEqual(same.wakeupsPerSecond, 0)
        let back = ProcessSample(cpuNanos: 1, energyNanojoules: 1, footprintBytes: 0, wakeups: 1, at: 6)
        let r = ProcessMeter.rates(from: a, to: back)
        expectEqual(r.cpuPercent, 0); expectEqual(r.energyMilliwatts, 0); expectEqual(r.wakeupsPerSecond, 0)
    }
    test("Meter: median of rounds (odd, even, empty)") {
        expectEqual(ProcessMeter.median([3, 1, 2]), 2)
        expectEqual(ProcessMeter.median([4, 1, 3, 2]), 2.5)
        expectEqual(ProcessMeter.median([]), 0)
    }
    test("Meter: a live sample sees this process (footprint, CPU time grows with work)") {
        let a = ProcessMeter.sample()
        var x = 0.0
        for i in 0..<3_000_000 { x += sin(Double(i)) }
        let b = ProcessMeter.sample()
        expect(a.footprintBytes > 1_000_000, "footprint \(a.footprintBytes)")
        expect(b.cpuNanos > a.cpuNanos, "CPU time \(a.cpuNanos) -> \(b.cpuNanos) (work \(x))")
        expect(b.at >= a.at)
        expect(ProcessMeter.load1() >= 0, "load average readable")
    }
}
