// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// What this process costs, read from the kernel (proc_pid_rusage): CPU time, the kernel's CPU energy estimate,
// memory footprint and wakeups. Used by the headless playback benchmark (App/PlaybackBench.swift).
// Foundation only, so it is unit-tested.
import Foundation
import Darwin

struct ProcessSample: Equatable {
    var cpuNanos: UInt64
    var energyNanojoules: UInt64
    var footprintBytes: UInt64
    var wakeups: UInt64
    var at: TimeInterval
}

struct ProcessRates: Equatable {
    var cpuPercent: Double         // of one core
    var energyMilliwatts: Double   // average CPU power the kernel attributes to this process
    var footprintMB: Double        // at the later sample
    var wakeupsPerSecond: Double
}

enum ProcessMeter {
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var i = mach_timebase_info_data_t()
        mach_timebase_info(&i)
        return (UInt64(i.numer), UInt64(max(1, i.denom)))
    }()

    static func sample(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> ProcessSample {
        var ri = rusage_info_v6()
        let rc = withUnsafeMutablePointer(to: &ri) { p in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0) }
        }
        guard rc == 0 else { return ProcessSample(cpuNanos: 0, energyNanojoules: 0, footprintBytes: 0, wakeups: 0, at: now) }
        // ri_user_time and ri_system_time are Mach time units, which are not nanoseconds on Apple silicon.
        let cpu = (ri.ri_user_time + ri.ri_system_time) * timebase.numer / timebase.denom
        return ProcessSample(cpuNanos: cpu, energyNanojoules: ri.ri_energy_nj, footprintBytes: ri.ri_phys_footprint,
                             wakeups: ri.ri_pkg_idle_wkups + ri.ri_interrupt_wkups, at: now)
    }

    /// Rates between two samples. No time between them, or counters that went backwards, give 0.
    static func rates(from a: ProcessSample, to b: ProcessSample) -> ProcessRates {
        let dt = b.at - a.at
        func perSecond(_ x: UInt64, _ y: UInt64) -> Double { dt > 0 && y >= x ? Double(y - x) / dt : 0 }
        return ProcessRates(cpuPercent: round2(perSecond(a.cpuNanos, b.cpuNanos) / 1e9 * 100),
                            energyMilliwatts: round2(perSecond(a.energyNanojoules, b.energyNanojoules) / 1e6),
                            footprintMB: round2(Double(b.footprintBytes) / 1_048_576),
                            wakeupsPerSecond: round2(perSecond(a.wakeups, b.wakeups)))
    }

    /// How far apart the playheads are, in ms. A player that can't read its video reports NaN: left out.
    static func spreadMilliseconds(_ times: [Double]) -> Double {
        let t = times.filter(\.isFinite)
        guard let hi = t.max(), let lo = t.min() else { return 0 }
        return ((hi - lo) * 1000).rounded()
    }
    /// A length in seconds, rounded to 0.1 s, for the report; nil when unknown (NaN or infinite).
    static func seconds(_ s: Double) -> Double? { s.isFinite ? (s * 10).rounded() / 10 : nil }
    /// The report with every NaN or infinite number replaced by null. JSONSerialization raises an Objective-C
    /// exception on either, which Swift can't catch, so one bad value would crash the benchmark.
    static func jsonSafe(_ v: Any) -> Any {
        switch v {
        case let d as Double: return d.isFinite ? d : NSNull()
        case let a as [Any]: return a.map(jsonSafe)
        case let o as [String: Any]: return o.mapValues(jsonSafe)
        default: return v
        }
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted(), m = s.count / 2
        return s.count % 2 == 1 ? s[m] : round2((s[m - 1] + s[m]) / 2)
    }

    /// The whole Mac's 1-minute load average. Other work skews CPU and energy figures, so the benchmark records it
    /// next to every measurement; compare builds only at similar load, or by ratios taken within one run.
    static func load1() -> Double {
        var l = [Double](repeating: 0, count: 3)
        return getloadavg(&l, 3) > 0 ? round2(l[0]) : -1
    }

    static var cpuBrand: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    private static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}
