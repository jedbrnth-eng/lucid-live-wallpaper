// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Download phases (no frozen 99%), size and duration checks, the conversion deadline and leftover cleanup.
import Foundation

/// Runs an async body from the synchronous test runner.
private final class AsyncBox<T>: @unchecked Sendable { var v: T?; let s = DispatchSemaphore(value: 0) }
private func blocking<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
    let b = AsyncBox<T>()
    Task.detached { b.v = await body(); b.s.signal() }
    b.s.wait()
    return b.v!
}

private final class Flag: @unchecked Sendable { var cancelled = false; var finished = false }

func registerDownloadTests() {
    // MARK: phases
    test("download phase: percent while bytes arrive, floor not round, clamped") {
        expectEqual(DownloadPhase.downloading(written: 63, expected: 100).label, "Downloading 63%")
        expectEqual(DownloadPhase.downloading(written: 999, expected: 1000).label, "Downloading 99%")
        expectEqual(DownloadPhase.downloading(written: 1000, expected: 1000).label, "Downloading 100%")
        expectEqual(DownloadPhase.downloading(written: 5000, expected: 1000).fraction, 1)
        expectNear(DownloadPhase.downloading(written: 25, expected: 100).fraction ?? -1, 0.25, 1e-9)
    }
    test("download phase: unknown size shows text and a spinner, not 1%") {
        let p = DownloadPhase.downloading(written: 12345, expected: -1)
        expectEqual(p, .downloading(fraction: nil))
        expectEqual(p.label, "Downloading…")
        expect(p.fraction == nil)
    }
    test("download phase: conversion steps have real text and no frozen percentage") {
        expectEqual(DownloadPhase.converting.label, "Converting for Mac…")
        expectEqual(DownloadPhase.looping.label, "Making a seamless loop…")
        expectEqual(DownloadPhase.checking.label, "Checking the file…")
        for p in [DownloadPhase.converting, .looping, .checking] {
            expect(p.fraction == nil, "\(p) must be indeterminate")
            expect(!p.label.contains("%"), "\(p.label) must not show a percentage")
        }
    }
    test("download steps: webm live clip converts, loops, then checks; photo only checks") {
        expectEqual(DownloadPolicy.steps(kind: .video, ext: "WebM", source: .live, seamlessLoops: true), [.converting, .looping, .checking])
        expectEqual(DownloadPolicy.steps(kind: .video, ext: "mp4", source: .live, seamlessLoops: true), [.looping, .checking])
        expectEqual(DownloadPolicy.steps(kind: .video, ext: "mp4", source: .live, seamlessLoops: false), [.checking])
        expectEqual(DownloadPolicy.steps(kind: .video, ext: "ogv", source: .wikimedia, seamlessLoops: true), [.converting, .checking])
        expectEqual(DownloadPolicy.steps(kind: .image, ext: "webm", source: .live, seamlessLoops: true), [.checking])
    }

    // MARK: size check
    test("size check: a cut-off download is rejected with a clear message") {
        let m = DownloadPolicy.sizeProblem(expected: 116_944_589, actual: 30_000_000)
        expect(m?.contains("cut off") == true, m ?? "nil")
        expect(m?.contains("30.0 MB") == true && m?.contains("116.9 MB") == true, m ?? "nil")
    }
    test("size check: exact size, unknown length and compressed transfers pass; empty and oversize fail") {
        expect(DownloadPolicy.sizeProblem(expected: 1000, actual: 1000) == nil)
        expect(DownloadPolicy.sizeProblem(expected: -1, actual: 1000) == nil)
        expect(DownloadPolicy.sizeProblem(expected: 0, actual: 1000) == nil)
        expect(DownloadPolicy.sizeProblem(expected: 400, actual: 1000, contentEncoding: "gzip") == nil)
        expect(DownloadPolicy.sizeProblem(expected: 400, actual: 1000, contentEncoding: "identity") != nil)
        expect(DownloadPolicy.sizeProblem(expected: 1000, actual: 0)?.contains("empty") == true)
        expect(DownloadPolicy.sizeProblem(expected: -1, actual: 0) != nil)
        expect(DownloadPolicy.sizeProblem(expected: 1000, actual: 1001) != nil)
    }
    test("duration check: ffmpeg's shorter output from a cut-off WebM is rejected") {
        // Measured: the first 30 MB of a 30.07 s 4K WebM converts (exit 0) to an 8.53 s clip.
        let m = DownloadPolicy.durationProblem(declared: 30.066, converted: 8.533)
        expect(m?.contains("incomplete") == true, m ?? "nil")
        expect(DownloadPolicy.durationProblem(declared: 30.066, converted: 30.0) == nil)
        expect(DownloadPolicy.durationProblem(declared: 30.066, converted: 28.0) == nil, "small container/stream differences pass")
        expect(DownloadPolicy.durationProblem(declared: nil, converted: 12) == nil)
        expect(DownloadPolicy.durationProblem(declared: 30, converted: nil) != nil)
        expect(DownloadPolicy.durationProblem(declared: 30, converted: 0) != nil)
        expect(DownloadPolicy.durationProblem(declared: .nan, converted: 5) == nil)
    }

    // MARK: photo end markers
    test("image end: a cut-off JPEG, PNG or WebP is caught; complete ones and other formats pass") {
        let msg = "cut off"
        let jpgHead: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10]
        expect(DownloadPolicy.imageEndProblem(head: jpgHead, tail: [0x12, 0x34, 0xFF, 0xD9], size: 4000) == nil)
        expect(DownloadPolicy.imageEndProblem(head: jpgHead, tail: [0xFF, 0xD9, 0, 0, 0], size: 4000) == nil, "padding after EOI is fine")
        expect(DownloadPolicy.imageEndProblem(head: jpgHead, tail: [0x12, 0x34, 0xFF, 0x00, 0x56], size: 4000)?.contains(msg) == true)
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let iend: [UInt8] = [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
        expect(DownloadPolicy.imageEndProblem(head: png, tail: [1, 2] + iend, size: 5000) == nil)
        expect(DownloadPolicy.imageEndProblem(head: png, tail: [1, 2, 3, 4, 5], size: 5000)?.contains(msg) == true)
        // RIFF size field = file size - 8 (little endian)
        let webp: (Int64) -> [UInt8] = { n in let v = UInt32(n - 8); return [0x52, 0x49, 0x46, 0x46, UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24), 0x57, 0x45, 0x42, 0x50] }
        expect(DownloadPolicy.imageEndProblem(head: webp(70_000), tail: [0], size: 70_000) == nil)
        expect(DownloadPolicy.imageEndProblem(head: webp(70_000), tail: [0], size: 30_000)?.contains(msg) == true)
        expect(DownloadPolicy.imageEndProblem(head: [0x49, 0x49, 0x2A, 0], tail: [1], size: 10) == nil, "TIFF not checked")
        expect(DownloadPolicy.imageEndProblem(head: [], tail: [], size: 0) == nil)
    }

    // MARK: leftovers
    test("leftovers: only regular .partial-* and *.loop.mp4 files, never library files") {
        let entries: [(name: String, isRegularFile: Bool)] = [
            (".partial-12-ABC", true), (".partial-3-X.webm", true), ("live-abc.loop.mp4", true), ("x.LOOP.MP4", true),
            ("live-abc.mp4", true), ("photo.jpg", true), (".DS_Store", true), ("partial-1", true), ("a.loop.mov", true),
            (".partial-dir", false), ("dir.loop.mp4", false), ("kept.loop.mp4", true),
        ]
        let got = DownloadPolicy.leftovers(entries, keep: ["kept.loop.mp4"])
        expectEqual(got, [".partial-12-ABC", ".partial-3-X.webm", "live-abc.loop.mp4", "x.LOOP.MP4"])
        expectEqual(DownloadPolicy.leftovers([]), [])
    }

    // MARK: deadline
    test("deadline: a hung step is cancelled and fails with a clear timeout") {
        let f = Flag()
        let t0 = Date()
        let r: String = blocking {
            do {
                _ = try await withDeadline(0.2) { () async throws -> Int in
                    do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { f.cancelled = true; throw error }
                    f.finished = true
                    return 1
                }
                return "returned"
            } catch let e as DownloadTimeout { return e.localizedDescription } catch { return "other: \(error)" }
        }
        expect(Date().timeIntervalSince(t0) < 5, "took \(Date().timeIntervalSince(t0)) s")
        expect(r.contains("longer than"), r)
        expect(f.cancelled && !f.finished, "the step must be cancelled")
        expectEqual(DownloadPolicy.conversionTimeout, 15 * 60)
        expect(DownloadTimeout(seconds: DownloadPolicy.conversionTimeout).localizedDescription.contains("15 minutes"))
        expect(DownloadTimeout(seconds: 3).localizedDescription.contains("3 seconds"))
    }
    test("deadline: a quick step returns its value; a failing step's error passes through") {
        let v: Int = blocking { (try? await withDeadline(5) { 42 }) ?? -1 }
        expectEqual(v, 42)
        struct Boom: Error {}
        let r: String = blocking {
            do { _ = try await withDeadline(5) { () async throws -> Int in throw Boom() }; return "returned" }
            catch is Boom { return "boom" } catch { return "other" }
        }
        expectEqual(r, "boom")
    }
}
