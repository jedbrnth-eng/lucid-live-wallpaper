// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Rules for importing your own videos and photos (pure, unit-tested): which files are accepted, how the copy in
// Application Support is named, path containment, folder walking that never follows symlinks out of the chosen
// folder, and the fit/fill/stretch + crop-focus layout maths.
import Foundation

enum Sniffed: Equatable { case video, image, unknown }

enum ImportCheck: Equatable { case ok(Kind), rejected(String) }

enum ImportPolicy {
    static let maxBytes: Int64 = 16 << 30   // 16 GB
    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi", "wmv", "flv", "ogv", "mpg", "mpeg", "ts"]
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp"]

    static func kind(forExtension e: String) -> Kind? {
        let x = e.lowercased()
        return videoExts.contains(x) ? .video : imageExts.contains(x) ? .image : nil
    }

    /// Look at the first bytes, not the name, so a renamed program or script can't pose as a wallpaper.
    static func sniff(_ x: [UInt8]) -> Sniffed {
        guard x.count >= 12 else { return .unknown }
        func at(_ o: Int, _ s: String) -> Bool { Array(s.utf8).enumerated().allSatisfy { o + $0.offset < x.count && x[o + $0.offset] == $0.element } }
        if at(4, "ftypheic") || at(4, "ftypheix") || at(4, "ftypmif1") || at(4, "ftypavif") { return .image }   // HEIC/AVIF stills
        if at(4, "ftyp") || at(4, "moov") || at(4, "mdat") || at(4, "wide") || at(4, "free") { return .video }   // MP4 / MOV
        if x[0] == 0x1A && x[1] == 0x45 && x[2] == 0xDF && x[3] == 0xA3 { return .video }                       // WebM / MKV
        if at(0, "RIFF") { return at(8, "WEBP") ? .image : .video }                                             // WebP / AVI
        // Exact still-image signatures first: "GIF8" starts with 0x47, which alone would look like an MPEG-TS sync byte.
        if (x[0] == 0xFF && x[1] == 0xD8) || at(1, "PNG") || at(0, "GIF8") || at(0, "II*") || at(0, "MM\u{0}*") { return .image }
        if at(0, "BM") && x[6] == 0 && x[7] == 0 && x[8] == 0 && x[9] == 0 { return .image }                     // BMP: reserved bytes are zero
        if at(0, "OggS") || x[0] == 0x47 || (x[0] == 0 && x[1] == 0 && x[2] == 1) { return .video }            // OGV, TS, MPEG
        if at(0, "FLV") || (x[0] == 0x30 && x[1] == 0x26 && x[2] == 0xB2) { return .video }                     // FLV, WMV
        return .unknown
    }

    /// Cheap checks before anything is copied. Decoding (damaged files) is checked by the caller with AVFoundation/ImageIO.
    static func check(ext: String, size: Int64, header: [UInt8]) -> ImportCheck {
        guard let k = kind(forExtension: ext) else { return .rejected("not a video or photo") }
        if size <= 0 { return .rejected("the file is empty") }
        if size > maxBytes { return .rejected("larger than 16 GB") }
        // The contents must be the kind the name claims (HEIC image sequences use video-style "ftyp" brands).
        let s = sniff(header)
        let heicLike = k == .image && ["heic", "heif"].contains(ext.lowercased()) && s == .video
        if s != (k == .video ? .video : .image) && !heicLike { return .rejected("the contents are not a video or photo") }
        return .ok(k)
    }

    static func sanitize(_ s: String, max: Int = 80) -> String {
        String(s.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }.prefix(max))
    }

    /// Name of the copy in Media/: sanitised title + size (base 36) + a letters/digits-only extension.
    static func destinationName(base: String, size: Int64, ext: String) -> String {
        let b = sanitize(base).isEmpty ? "wallpaper" : sanitize(base)
        let e = String(ext.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(5))
        return b + "-" + String(size, radix: 36) + "." + (e.isEmpty ? "bin" : e)
    }

    /// True when `path` (after resolving `..`) is a file strictly inside `dir`. Callers resolve symlinks first.
    static func isContained(_ path: String, in dir: String) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let d = URL(fileURLWithPath: dir).standardizedFileURL.pathComponents
        return p.count > d.count && Array(p.prefix(d.count)) == d
    }

    /// A file the library may delete: a real file (not a link) whose path, both as written and with links resolved,
    /// is strictly inside `root`. A hand-edited library.json can't make Lucid delete anything else.
    static func isSafeToDelete(_ path: String, inside root: URL) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              v.isSymbolicLink != true, v.isRegularFile == true else { return false }
        let std = url.standardizedFileURL.path, rootReal = root.resolvingSymlinksInPath().path
        return (isContained(std, in: root.standardizedFileURL.path) || isContained(std, in: rootReal))
            && isContained(url.resolvingSymlinksInPath().path, in: rootReal)
    }

    /// The item itself is a symbolic link (not followed).
    static func isSymlink(_ url: URL) -> Bool {
        (try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// Short tag from the first 1 MB of a file (48-bit FNV-1a, base 36), to tell apart different files that share a
    /// name and a size. Not a security hash: the caller still compares contents before treating files as the same.
    static func contentTag(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 1 << 20) else { return nil }
        var x: UInt64 = 0xcbf29ce484222325
        for b in d { x = (x ^ UInt64(b)) &* 0x100000001b3 }
        return String(x & 0xFFFF_FFFF_FFFF, radix: 36)
    }

    /// Video/photo files inside a folder the user chose: regular files only, hidden files and symlinks skipped
    /// (so a link can't pull in files from elsewhere), at most `limit`.
    static func mediaFiles(in folder: URL, limit: Int) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let root = folder.resolvingSymlinksInPath().path
        var out: [URL] = []
        while let f = e.nextObject() as? URL, out.count < limit {
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true, v.isRegularFile == true,
                  kind(forExtension: f.pathExtension) != nil,
                  isContained(f.resolvingSymlinksInPath().path, in: root) else { continue }
            out.append(f)
        }
        return out
    }
}

// MARK: - Fit / fill / stretch with crop focus

struct FrameRect: Equatable { var x, y, w, h: Double }

enum FillLayout {
    /// Frame of the media layer inside a bottom-left-origin host of size `bounds` (the host clips).
    /// focusX: 0 = keep the left edge, 1 = the right edge. focusY: 0 = keep the top, 1 = the bottom.
    static func frame(media: (w: Double, h: Double), bounds: (w: Double, h: Double), mode: FitMode, focusX: Double, focusY: Double) -> FrameRect {
        let full = FrameRect(x: 0, y: 0, w: bounds.w, h: bounds.h)
        guard media.w > 0, media.h > 0, bounds.w > 0, bounds.h > 0, mode != .stretch else { return full }
        let fx = min(1, max(0, focusX)), fy = min(1, max(0, focusY))
        let s = mode == .fill ? max(bounds.w / media.w, bounds.h / media.h) : min(bounds.w / media.w, bounds.h / media.h)
        let w = media.w * s, h = media.h * s
        if mode == .fit { return FrameRect(x: (bounds.w - w) / 2, y: (bounds.h - h) / 2, w: w, h: h) }
        return FrameRect(x: (bounds.w - w) * fx, y: (bounds.h - h) * (1 - fy), w: w, h: h)
    }
}
