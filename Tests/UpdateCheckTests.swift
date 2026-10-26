// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Optional update check (off by default): version comparison and a strict reader for GitHub's latest-release JSON.
import Foundation

private func ghFixture(_ name: String) throws -> Data {
    let root = ProcessInfo.processInfo.environment["LUCID_FIXTURES"] ?? "Tests/Fixtures"
    return try Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("github").appendingPathComponent(name))
}

func registerUpdateCheckTests() {
    test("Update: versions compare numerically, with or without a leading v") {
        expect(UpdateCheck.isNewer("v1.3.1", than: "1.3.0"))
        expect(UpdateCheck.isNewer("1.10.0", than: "1.9.9"), "10 > 9, not string order")
        expect(UpdateCheck.isNewer("2.0", than: "1.99.99"))
        expect(!UpdateCheck.isNewer("v1.3.0", than: "1.3.0"))
        expect(!UpdateCheck.isNewer("1.2.9", than: "1.3.0"))
        expect(!UpdateCheck.isNewer("v1.3.0-beta", than: "1.3.0"), "unparseable tags never prompt")
        expect(!UpdateCheck.isNewer("", than: "1.3.0"))
    }
    test("Update: the recorded GitHub response parses (v1.1.1) and is not newer than 1.3.0") {
        guard let r = UpdateCheck.parse(try ghFixture("releases-latest.json")) else { expect(false, "no release"); return }
        expectEqual(r.version, "1.1.1")
        expectEqual(r.page.absoluteString, "https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/tag/v1.1.1")
        expect(!UpdateCheck.isNewer(r.version, than: "1.3.0"))
    }
    test("Update: drafts, pre-releases, foreign links and junk are ignored") {
        let base = #"{"tag_name":"v9.0.0","html_url":"https://github.com/jedbrnth-eng/lucid-live-wallpaper/releases/tag/v9.0.0","draft":false,"prerelease":false}"#
        expectEqual(UpdateCheck.parse(Data(base.utf8))?.version, "9.0.0")
        expectEqual(UpdateCheck.parse(Data(base.replacingOccurrences(of: #""draft":false"#, with: #""draft":true"#).utf8)), nil)
        expectEqual(UpdateCheck.parse(Data(base.replacingOccurrences(of: #""prerelease":false"#, with: #""prerelease":true"#).utf8)), nil)
        expectEqual(UpdateCheck.parse(Data(base.replacingOccurrences(of: "https://github.com/jedbrnth-eng", with: "https://evil.example/jedbrnth-eng").utf8)), nil, "only our GitHub page is ever opened")
        expectEqual(UpdateCheck.parse(Data(base.replacingOccurrences(of: "https://github.com", with: "http://github.com").utf8)), nil, "HTTPS only")
        expectEqual(UpdateCheck.parse(Data(base.replacingOccurrences(of: "lucid-live-wallpaper/releases", with: "other-repo/releases").utf8)), nil)
        for junk in ["", "[]", "null", #"{"tag_name":5}"#, "<html>"] { expectEqual(UpdateCheck.parse(Data(junk.utf8)), nil, junk) }
        expectEqual(UpdateCheck.parse(Data(repeating: 0x20, count: UpdateCheck.maxBytes + 1)), nil, "size limit")
    }
    test("Update: checks at most once a day, never when off") {
        let t0 = Date(timeIntervalSince1970: 2_000_000_000)
        expect(UpdateCheck.shouldCheck(enabled: true, last: nil, now: t0))
        expect(!UpdateCheck.shouldCheck(enabled: false, last: nil, now: t0))
        expect(!UpdateCheck.shouldCheck(enabled: true, last: t0, now: t0.addingTimeInterval(23 * 3600)))
        expect(UpdateCheck.shouldCheck(enabled: true, last: t0, now: t0.addingTimeInterval(24 * 3600)))
    }
}
