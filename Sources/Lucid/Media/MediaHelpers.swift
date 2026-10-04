// Media probing, thumbnails and file helpers.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// MARK: - Media helpers

enum Media {
    /// Check the file's first bytes (not just its name) so a renamed program can't pose as a wallpaper.
    static func looksLikeMedia(_ u: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: u), let b = try? h.read(upToCount: 16), b.count >= 12 else { return false }
        try? h.close()
        let x = [UInt8](b)
        func at(_ o: Int, _ s: String) -> Bool { Array(s.utf8).enumerated().allSatisfy { o + $0.offset < x.count && x[o + $0.offset] == $0.element } }
        if at(4, "ftyp") || at(4, "moov") || at(4, "mdat") || at(4, "wide") || at(4, "free") { return true }   // MP4 / MOV / HEIC
        if x[0] == 0x1A && x[1] == 0x45 && x[2] == 0xDF && x[3] == 0xA3 { return true }                       // WebM / MKV
        if at(0, "RIFF") || at(0, "OggS") || x[0] == 0x47 || (x[0] == 0 && x[1] == 0 && x[2] == 1) { return true } // AVI/WebP, OGV, TS, MPEG
        if (x[0] == 0xFF && x[1] == 0xD8) || at(1, "PNG") || at(0, "GIF8") || at(0, "II*") || at(0, "MM\u{0}*") { return true } // JPG PNG GIF TIFF
        if at(0, "FLV") || (x[0] == 0x30 && x[1] == 0x26 && x[2] == 0xB2) { return true }                    // FLV, WMV
        return false
    }
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv", "flv", "ogv", "mpg", "mpeg", "ts"]
    static func kind(of url: URL) -> Kind? {
        let ext = url.pathExtension.lowercased()
        if videoExts.contains(ext) { return .video }
        guard let t = UTType(filenameExtension: ext) else { return nil }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return .video }
        if t.conforms(to: .image) { return .image }
        return nil
    }
    static func duration(_ path: String) async -> Double? {
        guard let d = try? await AVURLAsset(url: URL(fileURLWithPath: path)).load(.duration), d.seconds.isFinite else { return nil }
        return d.seconds
    }
    static func dims(_ path: String, _ kind: Kind) async -> (Int, Int)? {
        let url = URL(fileURLWithPath: path)
        if kind == .video {
            let a = AVURLAsset(url: url)
            guard let t = try? await a.loadTracks(withMediaType: .video).first,
                  let (size, tf) = try? await t.load(.naturalSize, .preferredTransform) else { return nil }
            let r = CGRect(origin: .zero, size: size).applying(tf)
            return (Int(abs(r.width).rounded()), Int(abs(r.height).rounded()))
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let o = p[kCGImagePropertyOrientation] as? Int ?? 1
        return o >= 5 ? (h, w) : (w, h)
    }
    static func writeJPEG(_ cg: CGImage, to url: URL, quality: Double = 0.85) -> Bool {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(d)
    }
    static func frame(_ path: String, maxSize: CGFloat, at seconds: Double = 1.5) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxSize, height: maxSize)
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity
        return try? await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }
    static func thumbnail(_ path: String, _ kind: Kind, id: String) async -> String? {
        let out = Paths.thumbs.appendingPathComponent("thumb-\(Paths.safe(id)).jpg")
        if FileManager.default.fileExists(atPath: out.path) { return out.path }
        var cg: CGImage?
        if kind == .video { cg = await frame(path, maxSize: 640) }
        else if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) {
            cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                              kCGImageSourceThumbnailMaxPixelSize: 640,
                                                              kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        }
        guard let cg, writeJPEG(cg, to: out) else { return nil }
        return out.path
    }
    /// Full-resolution still used as the macOS desktop picture behind a live video (Mission Control, other Spaces, after quit).
    static func poster(_ a: Assignment) async -> URL? {
        let out = Paths.thumbs.appendingPathComponent("poster-\(Paths.safe(a.itemID)).jpg")
        if FileManager.default.fileExists(atPath: out.path) { return out }
        guard let cg = await frame(a.path, maxSize: 3840), writeJPEG(cg, to: out, quality: 0.9) else { return nil }
        return out
    }
}
