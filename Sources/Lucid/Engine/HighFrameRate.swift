// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// "Half speed for 240 fps videos" (Settings, off by default). Apple's Aerials are filmed at 240 frames a second and
// every frame is decoded, although no display shows more than 120 (most 60), so they cost 2-4x any other loop. At
// half speed Lucid decodes half as many frames a second; the film moves in slow motion. A speed set on the wallpaper
// itself always wins. The rule is pure (unit-tested); FrameRates reads each file's rate once, before its window is
// made, so the window starts at the right speed.
import Foundation
import AVFoundation

enum HighFrameRate {
    /// 240 fps films (239.76 included); 120 fps and below keep their speed.
    static let threshold = 200.0

    static func speed(options: WallpaperOptions?, defaultSpeed: Double, fps: Double?, halfSpeedOn: Bool) -> Double {
        let o = options ?? WallpaperOptions()
        guard o.speed == nil, halfSpeedOn, let f = fps, f >= threshold else { return o.effectiveSpeed(default: defaultSpeed) }
        return o.effectiveSpeed(default: defaultSpeed / 2)
    }
}

/// Video frame rates by file, read once each (AVFoundation, asynchronously) and kept while Lucid runs.
@MainActor enum FrameRates {
    private static var known: [String: Double] = [:]
    private static var waiting: [String: [@MainActor () -> Void]] = [:]

    static func fps(_ path: String) -> Double? { known[path] }

    /// Reads the rate if it isn't known; `done` runs once it is (0 when the file can't be read, which plays normally).
    static func load(_ path: String, done: @escaping @MainActor () -> Void) {
        guard known[path] == nil else { return }
        if waiting[path] != nil { waiting[path]?.append(done); return }
        waiting[path] = [done]
        Task {
            known[path] = await read(path)
            (waiting.removeValue(forKey: path) ?? []).forEach { $0() }
        }
    }

    /// The rate, read now if it isn't known (the benchmark builds its windows directly).
    static func rate(_ path: String) async -> Double {
        if let r = known[path] { return r }
        let r = await read(path)
        known[path] = r
        return r
    }

    private static func read(_ path: String) async -> Double {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let t = try? await asset.loadTracks(withMediaType: .video).first, let r = try? await t.load(.nominalFrameRate) else { return 0 }
        return Double(r)
    }
}
