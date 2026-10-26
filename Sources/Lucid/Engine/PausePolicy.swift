// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Smart pausing, as pure logic: why playback should pause, the status line shown in Settings and the menu bar,
// a CPU gate with hysteresis, and when to release players after a long pause. The engine feeds in what it
// observes (power, lock, thermal, CPU ticks); nothing here reads the system, so it is fully unit-tested.
import Foundation

enum ThermalLevel: Int, Comparable, CaseIterable {
    case nominal, fair, serious, critical
    static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }
}

/// Why every display is paused. Order = priority (first match wins). `covered` is per display.
enum PauseReason: String, CaseIterable, Equatable {
    case user, locked, asleep, batteryLow, onBattery, lowPower, thermal, cpuBusy, covered
    var label: String {
        switch self {
        case .user: return "by you"
        case .locked: return "screen locked"
        case .asleep: return "display asleep"
        case .batteryLow: return "battery low"
        case .onBattery: return "on battery"
        case .lowPower: return "Low Power Mode"
        case .thermal: return "Mac is hot"
        case .cpuBusy: return "CPU busy"
        case .covered: return "full-screen app"
        }
    }
}

/// What the engine observed.
struct PowerSnapshot: Equatable {
    var userPaused = false
    var locked = false
    var asleep = false
    var onBattery = false
    var batteryPercent: Int?
    var lowPower = false
    var thermal: ThermalLevel = .nominal
    var cpuBusy = false     // output of CPUGate
}

/// The user's power-saving choices.
struct PausePrefs: Equatable {
    var pauseOnBattery: Bool
    var batteryBelowPercent: Int      // 0 = off
    var pauseLowPower: Bool
    var thermalLimit: ThermalLevel?   // nil = never pause for heat
    var cpuAbovePercent: Int          // 0 = off
    var pauseWhenCovered: Bool
}

enum PausePolicy {
    /// The reason every display is paused, or nil to play (subject to per-display covering).
    static func reason(_ s: PowerSnapshot, _ p: PausePrefs) -> PauseReason? {
        if s.userPaused { return .user }
        if s.locked { return .locked }
        if s.asleep { return .asleep }
        if s.onBattery, p.batteryBelowPercent > 0, let b = s.batteryPercent, b < p.batteryBelowPercent { return .batteryLow }
        if s.onBattery && p.pauseOnBattery { return .onBattery }
        if s.lowPower && p.pauseLowPower { return .lowPower }
        if let lim = p.thermalLimit, s.thermal >= lim { return .thermal }
        if s.cpuBusy && p.cpuAbovePercent > 0 { return .cpuBusy }
        return nil
    }
}

enum DisplayPlayback: Equatable { case playing, covered }

enum PlaybackStatus {
    /// "Playing", "Paused: Low Power Mode", "Playing (1 of 2 displays paused: full-screen app)".
    static func text(global: PauseReason?, displays: [DisplayPlayback]) -> String {
        if let g = global { return "Paused: \(g.label)" }
        if displays.isEmpty { return "No wallpaper playing" }
        let covered = displays.filter { $0 == .covered }.count
        if covered == 0 { return "Playing" }
        if covered == displays.count { return "Paused: \(PauseReason.covered.label)" }
        return "Playing (\(covered) of \(displays.count) displays paused: \(PauseReason.covered.label))"
    }
}

/// Cumulative CPU ticks for the whole Mac (host_statistics HOST_CPU_LOAD_INFO).
struct CPUTicks: Equatable {
    var user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
    /// Busy share of the time between two samples, or nil when it can't be told (no time passed, counters reset).
    static func busyFraction(from a: CPUTicks, to b: CPUTicks) -> Double? {
        guard b.user >= a.user, b.system >= a.system, b.idle >= a.idle, b.nice >= a.nice else { return nil }
        let busy = Double((b.user - a.user) + (b.system - a.system) + (b.nice - a.nice))
        let total = busy + Double(b.idle - a.idle)
        return total > 0 ? busy / total : nil
    }
}

/// Trips when the average of the last `window` samples reaches the threshold; releases 10 points below it,
/// so a wallpaper that pauses (and lowers the load itself) doesn't flap on and off.
struct CPUGate {
    var thresholdPercent: Int
    var window: Int
    private(set) var samples: [Double] = []
    private(set) var tripped = false

    init(thresholdPercent: Int, window: Int) { self.thresholdPercent = thresholdPercent; self.window = max(1, window) }

    mutating func feed(_ busy: Double) -> Bool {
        samples.append(min(1, max(0, busy)))
        if samples.count > window { samples.removeFirst(samples.count - window) }
        guard thresholdPercent > 0, samples.count == window else { tripped = false; return false }
        let avg = samples.reduce(0, +) / Double(samples.count)
        let on = Double(thresholdPercent) / 100, off = on - 0.1
        tripped = tripped ? avg >= off : avg >= on
        return tripped
    }
}

/// After a long pause, players and their decoded frames are released (the still desktop picture shows meanwhile)
/// and rebuilt on resume.
enum IdleRelease {
    static func shouldRelease(pausedSince: Date?, now: Date, afterMinutes: Int) -> Bool {
        guard let t = pausedSince, afterMinutes > 0 else { return false }
        let e = now.timeIntervalSince(t)
        return e >= 0 && e >= Double(afterMinutes) * 60
    }
}
