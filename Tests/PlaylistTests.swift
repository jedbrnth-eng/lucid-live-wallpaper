// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Playlists: interval and time-of-day schedules, shuffle without repeats, edits while playing, resume after relaunch.
import Foundation

struct SplitMix64: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}

private func at(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

func registerPlaylistTests() {
    let bkk = TimeZone(identifier: "Asia/Bangkok")!
    let ny = TimeZone(identifier: "America/New_York")!

    test("Playlist: interval schedule fires N minutes after the last change") {
        let last = at("2026-10-26T05:00:00Z")
        expectEqual(PlaylistScheduler.nextFire(lastChange: last, minutes: 30, times: nil, timeZone: bkk), at("2026-10-26T05:30:00Z"))
        expectEqual(PlaylistScheduler.nextFire(lastChange: last, minutes: 0, times: nil, timeZone: bkk), nil, "0 = never rotate")
    }
    test("Playlist: time-of-day schedule picks the next listed time, wrapping to tomorrow") {
        // 12:00 Bangkok = 05:00Z. Times 08:00, 18:30 -> next is 18:30 today (11:30Z).
        let last = at("2026-10-26T05:00:00Z")
        expectEqual(PlaylistScheduler.nextFire(lastChange: last, minutes: 60, times: [18 * 60 + 30, 8 * 60], timeZone: bkk), at("2026-10-26T11:30:00Z"))
        // 20:00 Bangkok -> 08:00 tomorrow
        expectEqual(PlaylistScheduler.nextFire(lastChange: at("2026-10-26T13:00:00Z"), minutes: 60, times: [480, 1110], timeZone: bkk), at("2026-10-27T01:00:00Z"))
        // Exactly at a listed time -> the next one, never the same instant
        expectEqual(PlaylistScheduler.nextFire(lastChange: at("2026-10-26T11:30:00Z"), minutes: 60, times: [480, 1110], timeZone: bkk), at("2026-10-27T01:00:00Z"))
    }
    test("Playlist: bad times are ignored; an all-bad list falls back to the interval") {
        let last = at("2026-10-26T05:00:00Z")
        expectEqual(PlaylistScheduler.sanitize([1500, -5, 600, 600, 30]), [30, 600])
        expectEqual(PlaylistScheduler.nextFire(lastChange: last, minutes: 45, times: [9999], timeZone: bkk), at("2026-10-26T05:45:00Z"))
        expectEqual(PlaylistScheduler.nextFire(lastChange: last, minutes: 45, times: [], timeZone: bkk), at("2026-10-26T05:45:00Z"))
    }
    test("Playlist: time-of-day across the New York DST switch uses wall-clock times") {
        // 2026-03-08 02:00 EST -> 03:00 EDT. Last change 2026-03-07 12:00 EST (17:00Z); 07:00 next morning is EDT (11:00Z).
        expectEqual(PlaylistScheduler.nextFire(lastChange: at("2026-03-07T17:00:00Z"), minutes: 60, times: [7 * 60], timeZone: ny), at("2026-03-08T11:00:00Z"))
    }

    test("Playlist: in-order playback wraps and previous steps back") {
        var r = PlaylistRun(playlistID: "p", ids: ["a", "b", "c"], shuffle: false, now: at("2026-10-26T00:00:00Z"))
        expectEqual(r.current, "a")
        var rng = SplitMix64(s: 1)
        for want in ["b", "c", "a"] { r.advance(ids: ["a", "b", "c"], shuffle: false, now: at("2026-10-26T01:00:00Z"), rng: &rng); expectEqual(r.current, want) }
        r.back(); expectEqual(r.current, "c")
        r.back(); expectEqual(r.current, "b")
        expectEqual(r.changedAt, at("2026-10-26T01:00:00Z"))
    }
    test("Playlist: shuffle shows every item once per round and never repeats across rounds") {
        var rng = SplitMix64(s: 42)
        let ids = (1...7).map { "i\($0)" }
        var r = PlaylistRun(playlistID: "p", ids: ids, shuffle: true, now: Date(timeIntervalSince1970: 0), rng: &rng)
        var seen = [r.current!]
        for _ in 1..<70 { r.advance(ids: ids, shuffle: true, now: Date(timeIntervalSince1970: 0), rng: &rng); seen.append(r.current!) }
        for round in 0..<10 { expectEqual(Set(seen[round * 7..<(round + 1) * 7]).count, 7, "round \(round) covers all") }
        for i in 1..<seen.count { expect(seen[i] != seen[i - 1], "no back-to-back repeat at \(i)") }
        // Two items: a reshuffle starts with the on-screen item half the time, so this exercises the swap.
        var two = PlaylistRun(playlistID: "p", ids: ["a", "b"], shuffle: true, now: Date(timeIntervalSince1970: 0), rng: &rng)
        var prev = two.current
        for i in 0..<40 {
            two.advance(ids: ["a", "b"], shuffle: true, now: Date(timeIntervalSince1970: 0), rng: &rng)
            expect(two.current != prev, "two-item playlist alternates (step \(i))"); prev = two.current
        }
    }
    test("Playlist: editing a playing playlist keeps the current item and adds new ones") {
        var rng = SplitMix64(s: 7)
        var r = PlaylistRun(playlistID: "p", ids: ["a", "b", "c"], shuffle: false, now: Date(timeIntervalSince1970: 0))
        r.advance(ids: ["a", "b", "c"], shuffle: false, now: Date(timeIntervalSince1970: 0), rng: &rng)   // on "b"
        r.reconcile(ids: ["b", "c", "d"], shuffle: false, rng: &rng)
        expectEqual(r.current, "b", "removing another item doesn't jump")
        expectEqual(r.order, ["b", "c", "d"])
        r.reconcile(ids: ["c", "d"], shuffle: false, rng: &rng)
        expectEqual(r.current, "c", "the current item was removed: move to the next one")
        r.reconcile(ids: [], shuffle: false, rng: &rng)
        expectEqual(r.current, nil)
    }
    test("Playlist: resume after relaunch: due when the next change has passed") {
        let r = PlaylistRun(playlistID: "p", ids: ["a", "b"], shuffle: false, now: at("2026-10-26T05:00:00Z"))
        expect(!PlaylistScheduler.isDue(r, minutes: 60, times: nil, timeZone: bkk, now: at("2026-10-26T05:59:59Z")))
        expect(PlaylistScheduler.isDue(r, minutes: 60, times: nil, timeZone: bkk, now: at("2026-10-26T06:00:00Z")))
        expect(!PlaylistScheduler.isDue(r, minutes: 0, times: nil, timeZone: bkk, now: at("2027-01-01T00:00:00Z")), "manual-only playlist")
        expect(!PlaylistScheduler.isDue(r, minutes: 60, times: nil, timeZone: bkk, now: at("2026-10-26T04:00:00Z")), "clock moved back: wait, don't spin")
    }
    test("Playlist: times typed by the user are parsed leniently and formatted back") {
        expectEqual(PlaylistScheduler.parseTimes("07:00, 18:30"), [420, 1110])
        expectEqual(PlaylistScheduler.parseTimes("18:30 7:05 7:05"), [425, 1110], "sorted, duplicates removed, single-digit hours")
        expectEqual(PlaylistScheduler.parseTimes("25:00, 7:60, abc, , 12"), [], "invalid entries are ignored")
        expectEqual(PlaylistScheduler.parseTimes(String(repeating: "1:00,", count: 5000)).count, 1, "huge input stays bounded")
        expectEqual(PlaylistScheduler.formatTimes([425, 1110]), "07:05, 18:30")
    }
    test("Playlist: runs and old playlists.json survive save/load") {
        let r = PlaylistRun(playlistID: "p", ids: ["a", "b"], shuffle: false, now: at("2026-10-26T05:00:00Z"))
        let back = PlaybackState.decode(try JSONEncoder().encode(PlaybackState(runs: ["*": r, "D1": r])))
        expectEqual(back.runs["*"], r)
        expectEqual(back.runs.count, 2)
        expectEqual(PlaybackState.decode(Data("garbage".utf8)).runs.count, 0)
        let mixed = #"{"runs":{"*":{"playlistID":"p","order":["a"],"position":0,"changedAt":0},"X":{"bogus":1}}}"#
        expectEqual(PlaybackState.decode(Data(mixed.utf8)).runs.keys.sorted(), ["*"], "a broken run is dropped alone")
        let old = #"[{"id":"p","name":"Mix","items":[],"shuffle":true,"minutes":30}]"#
        let p = SavedData.playlists(Data(old.utf8))
        expectEqual(p.first?.times, nil, "1.1.1/1.2.0 playlists have no times")
        let withTimes = #"[{"id":"p","name":"Mix","items":[],"shuffle":true,"minutes":30,"times":[480,"x"]}]"#
        expectEqual(SavedData.playlists(Data(withTimes.utf8)).first?.times, nil, "malformed times are dropped, the playlist is kept")
        expectEqual(SavedData.playlists(Data(withTimes.utf8)).first?.name, "Mix")
    }
}
