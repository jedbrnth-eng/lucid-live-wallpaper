// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// The light in a wallpaper's poster (its thumbnail, or the photo itself), for Day & Night "Pick for me".
import Foundation
import ImageIO
import CoreGraphics

enum PosterLight {
    /// Average light of an image file, read from a copy 24 pixels wide. Nil when the file can't be read.
    static func stats(path: String) -> LightStats? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                    kCGImageSourceThumbnailMaxPixelSize: 48,
                                                                    kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              img.width > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let w = 24, h = max(1, Int((Double(img.height) / Double(img.width) * 24).rounded()))
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? LightStats.from(rgba: px) : nil
    }
}
