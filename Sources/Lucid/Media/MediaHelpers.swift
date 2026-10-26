// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

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
    static func looksLikeMedia(_ u: URL) -> Bool { ImportPolicy.sniff(header(u)) != .unknown }
    static func header(_ u: URL) -> [UInt8] {
        guard let h = try? FileHandle(forReadingFrom: u) else { return [] }
        defer { try? h.close() }
        return [UInt8]((try? h.read(upToCount: 16)) ?? Data())
    }
    static func tailBytes(_ u: URL, _ n: Int) -> [UInt8] {
        guard let h = try? FileHandle(forReadingFrom: u) else { return [] }
        defer { try? h.close() }
        guard let end = try? h.seekToEnd() else { return [] }
        try? h.seek(toOffset: end > UInt64(n) ? end - UInt64(n) : 0)
        return [UInt8]((try? h.readToEnd()) ?? Data())
    }
    static func fileSize(_ u: URL) -> Int64 { (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int64) ?? 0 }
    static func kind(of url: URL) -> Kind? {
        let ext = url.pathExtension.lowercased()
        if let k = ImportPolicy.kind(forExtension: ext) { return k }
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
    /// nil when the file really decodes: a photo must be complete (ImageIO) and render a thumbnail; a video must be
    /// playable with a video track, a duration, and a frame near its end (a cut-off file fails that last read).
    static func verify(_ url: URL, _ kind: Kind) async -> String? {
        if kind == .image {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
                return "The downloaded file isn't a readable image." }
            guard CGImageSourceGetStatus(src) == .statusComplete, CGImageSourceGetStatusAtIndex(src, 0) == .statusComplete else {
                return "The downloaded image is incomplete; the download was probably cut off." }
            if let m = DownloadPolicy.imageEndProblem(head: header(url), tail: tailBytes(url, 4096), size: fileSize(url)) { return m }
            guard CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                               kCGImageSourceThumbnailMaxPixelSize: 256] as CFDictionary) != nil else {
                return "The downloaded image can't be decoded." }
            return nil
        }
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true,
              (try? await asset.loadTracks(withMediaType: .video))?.isEmpty == false,
              let d = try? await asset.load(.duration), d.seconds.isFinite, d.seconds > 0 else {
            return "The downloaded video can't be opened; it may be damaged or cut off." }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.maximumSize = CGSize(width: 320, height: 320)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = .zero
        let end = CMTime(seconds: max(0, d.seconds - 0.5), preferredTimescale: 600)
        guard (try? await gen.image(at: end)) != nil else {
            return "The downloaded video is incomplete; the download was probably cut off." }
        return nil
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
