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

/// The spectrum bars as shapes: one bar per band in its slot, bottom-aligned and at least 2 pt tall (`height` is a
/// full bar). The corner always fits the bar: CoreGraphics on macOS 15 aborts the app when a rounded rect's corner
/// is more than half a side, and every quiet 2 pt bar used to get the usual 3 pt corner.
enum SpectrumBars {
    static func shapes(_ bars: [Float], width: CGFloat, height: CGFloat) -> [(rect: CGRect, corner: CGFloat)] {
        let n = CGFloat(bars.count)
        guard width > 0, n > 0 else { return [] }
        let slot = width / n, barW = slot * 0.62
        return bars.enumerated().map { i, v in
            let bh = max(2, (v.isFinite ? CGFloat(max(v, 0)) : 0) * height)
            return (CGRect(x: CGFloat(i) * slot + (slot - barW) / 2, y: 0, width: barW, height: bh), max(0, min(3, barW / 2, bh / 2)))
        }
    }
}
