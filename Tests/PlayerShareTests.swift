// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Shared players: displays showing the same video at the same speed share one decoder.
import Foundation

func registerPlayerShareTests() {
    let clip = PlayerShareKey(path: "/m/aurora.mov", speed: 1)

    test("Shared players: two displays showing the same file at the same speed share one player") {
        var s = PlayerShare()
        expect(s.acquire(clip, holder: "display-1"), "the first display makes the player")
        expect(!s.acquire(clip, holder: "display-2"), "the second display reuses it instead of decoding the file again")
        expectEqual(s.count(clip), 2)
        expectEqual(s.players, 1)
    }
    test("Shared players: another speed or another file gets its own player") {
        var s = PlayerShare()
        s.acquire(clip, holder: "a")
        expect(s.acquire(PlayerShareKey(path: clip.path, speed: 0.5), holder: "b"), "same file at half speed")
        expect(s.acquire(PlayerShareKey(path: "/m/ocean.mp4", speed: 1), holder: "c"), "another file")
        expectEqual(s.players, 3)
    }
    test("Shared players: the player runs while any of its displays wants it (a covered display doesn't pause the other)") {
        var s = PlayerShare()
        s.acquire(clip, holder: "a"); s.acquire(clip, holder: "b")
        expect(!s.shouldRun(clip), "nobody asked to play yet")
        expect(s.setWantsRun(true, key: clip, holder: "a"))
        expect(s.setWantsRun(false, key: clip, holder: "b"), "b is covered, a still shows the video")
        expect(!s.setWantsRun(false, key: clip, holder: "a"), "both paused")
        expect(s.wantsRun(clip, holder: "b") == false)
    }
    test("Shared players: released with its last display only, and a leaving display can't keep it running") {
        var s = PlayerShare()
        s.acquire(clip, holder: "a"); s.acquire(clip, holder: "b")
        s.setWantsRun(true, key: clip, holder: "a"); s.setWantsRun(false, key: clip, holder: "b")
        expect(!s.release(clip, holder: "a"), "b still uses the player")
        expect(!s.shouldRun(clip), "a was the only display playing it")
        expect(s.release(clip, holder: "b"), "last display gone: release the player")
        expectEqual(s.players, 0)
        expect(!s.shouldRun(clip))
    }
    test("Shared players: unknown holders change nothing") {
        var s = PlayerShare()
        expect(!s.release(clip, holder: "ghost"), "releasing what was never acquired")
        expect(!s.setWantsRun(true, key: clip, holder: "ghost"), "a wish from a holder that isn't there")
        expectEqual(s.count(clip), 0)
        s.acquire(clip, holder: "a")
        expect(!s.acquire(clip, holder: "a"), "acquiring twice is still one holder")
        expectEqual(s.count(clip), 1)
        expect(s.release(clip, holder: "a"))
    }
    test("Shared players: a cross-fade on the same file hands the player over without a gap") {
        var s = PlayerShare()
        s.acquire(clip, holder: "old"); s.setWantsRun(true, key: clip, holder: "old")
        expect(!s.acquire(clip, holder: "new"), "the incoming window reuses the playing player")
        s.setWantsRun(true, key: clip, holder: "new")
        expect(!s.release(clip, holder: "old"), "the outgoing window lets go after the fade")
        expect(s.shouldRun(clip), "still playing for the new window")
    }
}
