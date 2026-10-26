// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Per-wallpaper "Audio reactive" look options and the pure mapping from audio levels to visual changes.
import Foundation

struct ReactiveOptions: Codable, Equatable, Hashable {
    var pulse = false   // zoom gently on bass
    var glow = false    // brighten with overall level
    var bars = false    // spectrum bars along the bottom edge
    var any: Bool { pulse || glow || bars }
}

struct ReactiveLook: Equatable {
    var scale: Float = 1   // 1 = no zoom
    var glow: Float = 0    // opacity of a soft additive light layer
    var bars: [Float] = [] // 0...1 heights, empty when bars are off
}

enum ReactiveMapper {
    static let maxZoom: Float = 0.06
    static let maxGlow: Float = 0.35

    static func look(_ f: AudioFrame, options o: ReactiveOptions) -> ReactiveLook {
        var l = ReactiveLook()
        let clamp: (Float) -> Float = { $0.isFinite ? min(1, max(0, $0)) : 0 }
        if o.pulse { l.scale = 1 + maxZoom * pow(clamp(f.bass), 1.5) }
        if o.glow { l.glow = maxGlow * clamp(f.level) }
        if o.bars { l.bars = AudioFrame.pad(f.spectrum).map(clamp) }
        return l
    }
}
