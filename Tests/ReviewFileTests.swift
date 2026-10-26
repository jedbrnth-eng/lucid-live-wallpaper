// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Regression tests for the 1.3.0 review: which files the library may delete, and how imports treat links and
// different files that share a name and size.
import Foundation

func registerReviewFileTests() {
    // H1: what remove() may delete.
    test("Review H1: only real files inside Media/Thumbs may be deleted, never a link or a path outside") {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lucid-del-\(UUID().uuidString)")
        let media = root.appendingPathComponent("Media"), thumbs = root.appendingPathComponent("Thumbs"), outside = root.appendingPathComponent("Docs")
        for d in [media, thumbs, outside] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: root) }
        try Data("v".utf8).write(to: media.appendingPathComponent("clip.mp4"))
        try Data("t".utf8).write(to: thumbs.appendingPathComponent("thumb-x.jpg"))
        try Data("secret".utf8).write(to: outside.appendingPathComponent("tax.pdf"))
        try fm.createSymbolicLink(at: outside.appendingPathComponent("my-link.mp4"), withDestinationURL: media.appendingPathComponent("clip.mp4"))
        try fm.createSymbolicLink(at: media.appendingPathComponent("evil.mp4"), withDestinationURL: outside.appendingPathComponent("tax.pdf"))
        expect(ImportPolicy.isSafeToDelete(media.appendingPathComponent("clip.mp4").path, inside: media))
        expect(ImportPolicy.isSafeToDelete(thumbs.appendingPathComponent("thumb-x.jpg").path, inside: thumbs))
        expect(!ImportPolicy.isSafeToDelete(outside.appendingPathComponent("tax.pdf").path, inside: thumbs), "thumbPath outside Thumbs")
        expect(!ImportPolicy.isSafeToDelete(thumbs.appendingPathComponent("../Docs/tax.pdf").path, inside: thumbs), ".. out of Thumbs")
        expect(!ImportPolicy.isSafeToDelete(outside.appendingPathComponent("my-link.mp4").path, inside: media), "a link outside that points into Media")
        expect(!ImportPolicy.isSafeToDelete(media.appendingPathComponent("evil.mp4").path, inside: media), "a link inside that points out")
        expect(!ImportPolicy.isSafeToDelete(media.path, inside: media), "the folder itself")
        expect(!ImportPolicy.isSafeToDelete(media.appendingPathComponent("missing.mp4").path, inside: media))
    }

    // H2: links and same-name/same-size files on import.
    test("Review H2: symlinks are detected without following them; content tags tell same-size files apart") {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lucid-imp-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let a = root.appendingPathComponent("IMG_0001.jpg"), b = root.appendingPathComponent("b.jpg"), l = root.appendingPathComponent("link.jpg")
        try Data((0..<5000).map { UInt8($0 % 251) }).write(to: a)
        try Data((0..<5000).map { UInt8(($0 * 7) % 251) }).write(to: b)
        try fm.createSymbolicLink(at: l, withDestinationURL: a)
        expect(ImportPolicy.isSymlink(l)); expect(!ImportPolicy.isSymlink(a))
        let ta = ImportPolicy.contentTag(a), tb = ImportPolicy.contentTag(b)
        expect(ta != nil && tb != nil && ta != tb, "\(String(describing: ta)) \(String(describing: tb))")
        expectEqual(ImportPolicy.contentTag(a), ta, "stable")
        expect(ta.map { $0.count <= 12 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } } ?? false)
    }
}
