// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Headless screenshots of app screens (started by Headless.swift, never on screen). The library is a set of
// generated posters, so screenshots never show anyone's real wallpapers. Each screen is rendered at 2x in a window
// that is never ordered front, after its suggestions and thumbnails have loaded.
import SwiftUI
import AppKit
import ImageIO

@MainActor enum DevShots {
    /// A generated poster: a sky gradient (top to bottom), optional sun or moon, stars and hills.
    struct Poster {
        let name: String
        let sky: [UInt32]
        var sun: (x: Double, y: Double, r: Double, color: UInt32)?
        var stars = false
        var hills: UInt32?
    }
    static let posters: [Poster] = [
        Poster(name: "Harbour", sky: [0x050A24, 0x0D1B44, 0x1A2C5C], sun: (0.78, 0.72, 46, 0xE8ECFF), stars: true, hills: 0x03061A),
        Poster(name: "Lagoon", sky: [0x2A2B5E, 0xB4668E, 0xF2B09A], sun: (0.42, 0.30, 70, 0xFFE2C2), hills: 0x3A2448),
        Poster(name: "Ridge", sky: [0x3D8FE0, 0x8CC6F7, 0xD7ECFF], sun: (0.2, 0.82, 52, 0xFFFBEA), hills: 0x2F7A57),
        Poster(name: "Ember", sky: [0x2A1033, 0xC2462B, 0xFFB45A], sun: (0.62, 0.26, 96, 0xFFE09A), hills: 0x1E0C1E),
        Poster(name: "Concrete", sky: [0x5E5F66, 0x8A8B92, 0xB3B4BA]),
        Poster(name: "Glacier", sky: [0x9ED7EA, 0xD8F1F8, 0xF6FCFF], hills: 0xC6E4EE),
    ]

    static func run(to dir: URL) async -> [String] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store.shared
        let demo = Paths.make(Paths.support.appendingPathComponent("demo", isDirectory: true))
        for p in posters.reversed() {   // the library lists the newest first
            let u = demo.appendingPathComponent(p.name + ".png")
            if draw(p, to: u) { _ = await store.importOne(u, move: false, site: nil, page: nil) }
        }
        var written: [String] = []
        if let f = await shot(DayNightSheet(target: DNTarget(screenKey: nil, name: "All Displays")), width: 600, name: "daynight-sheet", in: dir) {
            written.append(f)
        }
        return written
    }

    private static func rgb(_ c: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((c >> 16) & 0xFF) / 255, green: CGFloat((c >> 8) & 0xFF) / 255, blue: CGFloat(c & 0xFF) / 255, alpha: 1)
    }

    private static func draw(_ p: Poster, to u: URL) -> Bool {
        let w = 1600, h = 900
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let sky = CGGradient(colorsSpace: space, colors: p.sky.map(rgb) as CFArray, locations: nil) else { return false }
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: h), end: .zero, options: [])
        if p.stars {
            var seed: UInt64 = 0x2545F4914F6CDD1D
            for _ in 0..<260 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let x = Double(seed >> 40 & 0xFFFF) / 65535 * Double(w), y = (0.35 + Double(seed >> 20 & 0xFFFF) / 65535 * 0.65) * Double(h)
                let r = 0.8 + Double(seed & 0x3) * 0.6
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35 + Double(seed >> 8 & 0x7) / 14))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
        }
        if let s = p.sun {
            ctx.setFillColor(rgb(s.color))
            ctx.fillEllipse(in: CGRect(x: s.x * Double(w) - s.r, y: s.y * Double(h) - s.r, width: s.r * 2, height: s.r * 2))
        }
        if let g = p.hills {
            ctx.setFillColor(rgb(g))
            ctx.move(to: .zero)
            for x in stride(from: 0, through: w, by: 20) {
                let t = Double(x) / Double(w)
                ctx.addLine(to: CGPoint(x: Double(x), y: Double(h) * (0.2 + 0.06 * sin(t * 7.1) + 0.03 * sin(t * 17.3 + 1))))
            }
            ctx.addLine(to: CGPoint(x: w, y: 0)); ctx.closePath(); ctx.fillPath()
        }
        guard let img = ctx.makeImage(), let d = CGImageDestinationCreateWithURL(u as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(d, img, nil)
        return CGImageDestinationFinalize(d)
    }

    /// Renders a view at 2x in a window that is never ordered front and writes `<name>.png`.
    private static func shot<V: View>(_ v: V, width: CGFloat, name: String, in dir: URL) async -> String? {
        let host = NSHostingView(rootView: v.lucidEnvironment(Store.shared).preferredColorScheme(.dark).background(Theme.bg2))
        let win = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        try? await Task.sleep(nanoseconds: 3_500_000_000)   // suggestions and poster thumbnails load
        let h = min(2400, max(200, host.fittingSize.height))
        host.frame = NSRect(x: 0, y: 0, width: width, height: h)
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 500_000_000)
        defer { win.contentView = nil }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(h * 2), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: width, height: h)
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let u = dir.appendingPathComponent(name + ".png")
        return (try? png.write(to: u)) != nil ? u.path : nil
    }
}
