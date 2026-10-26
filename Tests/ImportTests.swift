// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Importing your own files: what is accepted, how the copy is named, path containment, fit/fill/stretch + crop focus,
// and per-wallpaper options surviving a save/load.
import Foundation

private func bytes(_ s: String, pad: Int = 16) -> [UInt8] { Array(s.utf8) + Array(repeating: 0, count: max(0, pad - s.utf8.count)) }

func registerImportTests() {
    let mp4 = [0, 0, 0, 0x18] + bytes("ftypmp42")
    let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D]
    let jpg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1]
    let webm: [UInt8] = [0x1A, 0x45, 0xDF, 0xA3, 1, 0, 0, 0, 0, 0, 0, 0x1F]
    let exe: [UInt8] = [0x4D, 0x5A, 0x90, 0, 3, 0, 0, 0, 4, 0, 0, 0]          // Windows .exe ("MZ")
    let macho: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0, 0, 1, 0, 0, 0, 0]  // Mach-O arm64
    let script = bytes("#!/bin/sh\nrm -rf")

    test("Import: sniffing recognises real media headers") {
        expectEqual(ImportPolicy.sniff(mp4), .video)
        expectEqual(ImportPolicy.sniff(webm), .video)
        expectEqual(ImportPolicy.sniff(png), .image)
        expectEqual(ImportPolicy.sniff(jpg), .image)
    }
    test("Import: programs, scripts and truncated files are not media") {
        expectEqual(ImportPolicy.sniff(exe), .unknown)
        expectEqual(ImportPolicy.sniff(macho), .unknown)
        expectEqual(ImportPolicy.sniff(script), .unknown)
        expectEqual(ImportPolicy.sniff([0xFF, 0xD8]), .unknown, "fewer than 12 bytes")
        expectEqual(ImportPolicy.sniff([]), .unknown)
    }
    test("Import: check accepts MP4/MOV/WebM/photos and rejects with a clear reason") {
        expectEqual(ImportPolicy.check(ext: "MP4", size: 5_000_000, header: mp4), .ok(.video))
        expectEqual(ImportPolicy.check(ext: "mov", size: 5_000_000, header: mp4), .ok(.video))
        expectEqual(ImportPolicy.check(ext: "webm", size: 5_000_000, header: webm), .ok(.video))
        expectEqual(ImportPolicy.check(ext: "png", size: 900, header: png), .ok(.image))
        expectEqual(ImportPolicy.check(ext: "exe", size: 900, header: exe), .rejected("not a video or photo"))
        expectEqual(ImportPolicy.check(ext: "mp4", size: 900, header: exe), .rejected("the contents are not a video or photo"))
        expectEqual(ImportPolicy.check(ext: "jpg", size: 0, header: []), .rejected("the file is empty"))
        expectEqual(ImportPolicy.check(ext: "mp4", size: ImportPolicy.maxBytes + 1, header: mp4), .rejected("larger than 16 GB"))
    }
    test("Import: copied file names are sanitised (no traversal, no hidden files, bounded length)") {
        let n = ImportPolicy.destinationName(base: "../../etc/passwd", size: 1234, ext: "mp4")
        expect(!n.contains("/") && !n.contains("..") && !n.hasPrefix("."), n)
        expect(n.hasSuffix(".mp4"), n)
        expectEqual(ImportPolicy.destinationName(base: "My Clip (4K)", size: 35, ext: "MOV"), "My_Clip__4K_-z.mov")
        expectEqual(ImportPolicy.destinationName(base: "", size: 1, ext: "png"), "wallpaper-1.png")
        expectEqual(ImportPolicy.destinationName(base: "x", size: 1, ext: "p/n\u{0}g"), "x-1.png", "extension keeps only letters/digits")
        expect(ImportPolicy.destinationName(base: String(repeating: "a", count: 500), size: 1, ext: "mp4").count <= 96)
        expectEqual(ImportPolicy.destinationName(base: "บ้าน", size: 1, ext: "jpg"), "บ้าน-1.jpg", "non-Latin letters are fine")
    }
    test("Import: containment check defeats ../ traversal and prefix tricks") {
        expect(ImportPolicy.isContained("/a/Lucid/Media/x.mp4", in: "/a/Lucid/Media"))
        expect(!ImportPolicy.isContained("/a/Lucid/Media/../x.mp4", in: "/a/Lucid/Media"))
        expect(!ImportPolicy.isContained("/a/Lucid/MediaEvil/x.mp4", in: "/a/Lucid/Media"), "sibling with the same prefix")
        expect(!ImportPolicy.isContained("/a/Lucid/Media", in: "/a/Lucid/Media"), "the folder itself is not a file in it")
    }
    test("Import: folder import skips symlinks that point outside the chosen folder") {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lucid-import-\(UUID().uuidString)")
        let chosen = root.appendingPathComponent("chosen"), outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: chosen.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data(mp4).write(to: chosen.appendingPathComponent("a.mp4"))
        try Data(png).write(to: chosen.appendingPathComponent("sub/b.png"))
        try Data(png).write(to: outside.appendingPathComponent("secret.png"))
        try Data("x".utf8).write(to: chosen.appendingPathComponent(".hidden.png"))
        try fm.createSymbolicLink(at: chosen.appendingPathComponent("link.png"), withDestinationURL: outside.appendingPathComponent("secret.png"))
        try fm.createSymbolicLink(at: chosen.appendingPathComponent("linkdir"), withDestinationURL: outside)
        let found = ImportPolicy.mediaFiles(in: chosen, limit: 100).map(\.lastPathComponent).sorted()
        expectEqual(found, ["a.mp4", "b.png"])
        expectEqual(ImportPolicy.mediaFiles(in: chosen, limit: 1).count, 1, "limit is honoured")
    }

    test("Layout: fill covers the screen and crop focus picks the visible part") {
        let screen = (w: 1000.0, h: 500.0)
        let tall = (w: 1000.0, h: 1000.0)  // square media on a 2:1 screen: 500 pt of height is cropped
        expectEqual(FillLayout.frame(media: tall, bounds: screen, mode: .fill, focusX: 0.5, focusY: 0.5), FrameRect(x: 0, y: -250, w: 1000, h: 1000))
        expectEqual(FillLayout.frame(media: tall, bounds: screen, mode: .fill, focusX: 0.5, focusY: 0), FrameRect(x: 0, y: -500, w: 1000, h: 1000), "top kept")
        expectEqual(FillLayout.frame(media: tall, bounds: screen, mode: .fill, focusX: 0.5, focusY: 1), FrameRect(x: 0, y: 0, w: 1000, h: 1000), "bottom kept")
        let wide = (w: 4000.0, h: 1000.0)
        expectEqual(FillLayout.frame(media: wide, bounds: screen, mode: .fill, focusX: 0, focusY: 0.5), FrameRect(x: 0, y: 0, w: 2000, h: 500), "left kept")
        expectEqual(FillLayout.frame(media: wide, bounds: screen, mode: .fill, focusX: 1, focusY: 0.5), FrameRect(x: -1000, y: 0, w: 2000, h: 500), "right kept")
    }
    test("Layout: fit letterboxes centred, stretch fills exactly, bad sizes fall back to the screen") {
        let screen = (w: 1000.0, h: 500.0)
        expectEqual(FillLayout.frame(media: (w: 1000, h: 1000), bounds: screen, mode: .fit, focusX: 0, focusY: 0), FrameRect(x: 250, y: 0, w: 500, h: 500))
        expectEqual(FillLayout.frame(media: (w: 1000, h: 1000), bounds: screen, mode: .stretch, focusX: 0.5, focusY: 0.5), FrameRect(x: 0, y: 0, w: 1000, h: 500))
        expectEqual(FillLayout.frame(media: (w: 0, h: 0), bounds: screen, mode: .fill, focusX: 0.5, focusY: 0.5), FrameRect(x: 0, y: 0, w: 1000, h: 500))
        expectEqual(FillLayout.frame(media: (w: 100, h: 100), bounds: screen, mode: .fill, focusX: 9, focusY: -3),
                    FillLayout.frame(media: (w: 100, h: 100), bounds: screen, mode: .fill, focusX: 1, focusY: 0), "focus is clamped to 0...1")
    }

    test("Options: per-wallpaper fit/focus/speed survive save/load and old files still decode") {
        let o = WallpaperOptions(fit: .stretch, focusX: 0.2, focusY: 0.8, speed: 0.5)
        let a = Assignment(itemID: "x", title: "X", path: "/x.mp4", kind: .video, reactive: nil, options: o)
        let back = try JSONDecoder().decode(Assignment.self, from: JSONEncoder().encode(a))
        expectEqual(back.options, o)
        expect(a.sameMedia(Assignment(itemID: "x", title: "X", path: "/x.mp4", kind: .video)), "options are applied in place, not a reload")
        let old = try JSONDecoder().decode(Assignment.self, from: Data(#"{"itemID":"x","title":"X","path":"/x.mp4","kind":"video"}"#.utf8))
        expectEqual(old.options, nil)
        let item = SavedData.items(Data(#"[{"id":"local:x","source":"local","kind":"video","title":"X","width":1,"height":1,"options":{"fit":"zoomy","speed":2}}]"#.utf8))
        expectEqual(item.first?.options?.fit, nil, "an unknown fit value is dropped, the item and other options are kept")
        expectEqual(item.first?.options?.speed, 2)
    }
    test("Options: speed is clamped to a sane range and defaults apply") {
        expectEqual(WallpaperOptions(speed: 50).effectiveSpeed(default: 1), 4)
        expectEqual(WallpaperOptions(speed: 0).effectiveSpeed(default: 1), 0.25)
        expectEqual(WallpaperOptions().effectiveSpeed(default: 0.75), 0.75)
        expectEqual(WallpaperOptions().effectiveFit(defaultFill: false), .fit)
        expectEqual(WallpaperOptions(fit: .stretch).effectiveFit(defaultFill: true), .stretch)
    }
}
