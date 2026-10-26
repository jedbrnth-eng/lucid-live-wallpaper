// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Regression tests for the second 1.3.0 review: download file names, stopping stuck tools, leftover cleanup,
// Home rows with missing dates.
import Foundation

private final class RunBox<T>: @unchecked Sendable { var v: T?; let s = DispatchSemaphore(value: 0) }
private func runBlocking<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
    let b = RunBox<T>()
    Task.detached { b.v = await body(); b.s.signal() }
    b.s.wait()
    return b.v!
}

func registerFinalFixTests() {
    // HIGH-1: the saved extension comes from catalog/provider data and must never become a path.
    test("download ext: a hostile file extension can't leave Media/") {
        let media = URL(fileURLWithPath: "/tmp/LucidSupport/Media", isDirectory: true)
        for bad in ["../../x", "mp4/../../../etc/passwd", "a/b", "..", "/", "mp4\u{0}x", " webm ", "m p 4"] {
            let ext = DownloadPolicy.downloadExt(fileExt: bad, downloadURL: nil, kind: .video)
            expect(!ext.isEmpty && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }, "\(bad.debugDescription) -> \(ext.debugDescription)")
            let tmp = media.appendingPathComponent(".partial-1-UUID.\(ext)").standardizedFileURL
            expectEqual(tmp.deletingLastPathComponent().path, media.path, "\(bad.debugDescription) escapes Media/")
        }
        let longExt = DownloadPolicy.downloadExt(fileExt: String(repeating: "a", count: 300), downloadURL: nil, kind: .video)
        expect(longExt.count <= 10, "length \(longExt.count)")
    }
    test("download ext: normal extensions are unchanged") {
        expectEqual(DownloadPolicy.downloadExt(fileExt: "webm", downloadURL: nil, kind: .video), "webm")
        expectEqual(DownloadPolicy.downloadExt(fileExt: "mp4", downloadURL: "https://x/y.webm", kind: .video), "mp4")
        expectEqual(DownloadPolicy.downloadExt(fileExt: nil, downloadURL: "https://x/y.ogv?a=1", kind: .video), "ogv")
        expectEqual(DownloadPolicy.downloadExt(fileExt: nil, downloadURL: "https://x/photo.jpeg", kind: .image), "jpeg")
        expectEqual(DownloadPolicy.downloadExt(fileExt: "", downloadURL: nil, kind: .video), "bin")
        expectEqual(DownloadPolicy.downloadExt(fileExt: nil, downloadURL: "https://x/noext", kind: .image), "bin")
    }

    // HIGH-2: a tool that ignores SIGTERM must still stop, so the 15-minute limit can't hang forever.
    test("process: a tool that ignores SIGTERM is killed soon after the deadline") {
        let t0 = Date()
        let r: String = runBlocking {
            do {
                _ = try await withDeadline(0.5) {
                    try await ProcessRunner.run("/usr/bin/perl", ["-e", "$SIG{TERM}='IGNORE'; sleep 30"])
                }
                return "returned"
            } catch is DownloadTimeout { return "timeout" } catch { return "other: \(error)" }
        }
        let took = Date().timeIntervalSince(t0)
        expectEqual(r, "timeout")
        expect(took < 6, "took \(took) s (SIGTERM ignored, no SIGKILL)")
    }
    // HIGH-2: output larger than the pipe buffer must not block the tool.
    test("process: a tool printing more than the pipe buffer finishes and returns all output") {
        let t0 = Date()
        let r: String = runBlocking {
            do {
                let out = try await withDeadline(5) {
                    try await ProcessRunner.run("/usr/bin/perl", ["-e", "print 'a' x 300000"])
                }
                return "status=\(out.status) bytes=\(out.output.utf8.count)"
            } catch { return "error: \(error)" }
        }
        expectEqual(r, "status=0 bytes=300000")
        expect(Date().timeIntervalSince(t0) < 5, "took \(Date().timeIntervalSince(t0)) s")
    }
    test("process: a normal tool still returns its status and output; cancel stops it") {
        let ok: String = runBlocking {
            (try? await ProcessRunner.run("/bin/echo", ["hi"])).map { "\($0.status) \($0.output)" } ?? "error"
        }
        expectEqual(ok, "0 hi\n")
        let bad: Int32 = runBlocking { (try? await ProcessRunner.run("/usr/bin/false", []))?.status ?? -1 }
        expectEqual(bad, 1)
        let t0 = Date()
        let c: String = runBlocking {
            let t = Task { try await ProcessRunner.run("/bin/sleep", ["30"]) }
            try? await Task.sleep(nanoseconds: 300_000_000)
            t.cancel()
            do { _ = try await t.value; return "returned" } catch { return "threw" }
        }
        expect(Date().timeIntervalSince(t0) < 5, "cancel took \(Date().timeIntervalSince(t0)) s")
        expect(c == "threw" || c == "returned", c)
    }

    // MED-4: launch cleanup must never delete a user's own file.
    test("leftovers: a user's own *.loop.mp4 is kept; only Lucid's old live_*.loop.mp4 halves go") {
        let entries: [(name: String, isRegularFile: Bool)] = [
            ("my holiday.loop.mp4", true), ("Beach.LOOP.MP4", true), ("live_abc.loop.mp4", true), ("LIVE_def.loop.mp4", true),
            (".partial-1-X.mp4", true),
        ]
        expectEqual(DownloadPolicy.leftovers(entries), ["live_abc.loop.mp4", "LIVE_def.loop.mp4", ".partial-1-X.mp4"])
    }
    test("leftovers: the library's own files are kept whatever their letter case") {
        let entries: [(name: String, isRegularFile: Bool)] = [("live_Kept.loop.mp4", true), (".partial-Kept", true)]
        expectEqual(DownloadPolicy.leftovers(entries, keep: ["live_kept.LOOP.mp4", ".PARTIAL-kept"]), [])
    }

    // LOW-1: a library item without an added date must not crash the Home rows.
    test("home rows: items without an added date don't crash 'New in your library'") {
        var a = WallItem(id: "a", source: .local, kind: .video, title: "A", width: 1, height: 1)
        a.localPath = "/a.mp4"
        var b = WallItem(id: "b", source: .local, kind: .video, title: "B", width: 1, height: 1)
        b.localPath = "/b.mp4"; b.addedAt = Date(timeIntervalSince1970: 0)
        let i = HomeInput(library: [a, b], live: [], aerials: [], favorites: [], usage: UsageLog(), featuredIDs: [],
                          themes: [], now: .distantPast, isReady: { $0.localPath != nil }, theme: { _ in "Space" })
        let rows = HomeBuilder.rows(i)
        expect(!rows.isEmpty)
    }
}
