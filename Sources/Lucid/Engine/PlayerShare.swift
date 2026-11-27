// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Which wallpaper windows share a video player, as pure bookkeeping (the players live in SharedPlayers.swift).
// Windows showing the same file at the same speed share one looping player, so the video is decoded once however
// many displays show it, and every display shows the same frame. The player runs while at least one of its windows
// wants it (another may be covered) and is released with its last window.
import Foundation

struct PlayerShareKey: Hashable {
    var path: String
    var speed: Double
}

struct PlayerShare {
    /// key -> holder (one wallpaper window) -> whether that window wants the video running
    private(set) var holders: [PlayerShareKey: [String: Bool]] = [:]

    var players: Int { holders.count }
    func count(_ k: PlayerShareKey) -> Int { holders[k]?.count ?? 0 }
    func wantsRun(_ k: PlayerShareKey, holder: String) -> Bool { holders[k]?[holder] ?? false }
    func shouldRun(_ k: PlayerShareKey) -> Bool { holders[k]?.values.contains(true) ?? false }

    /// Adds a window to a player. True when it is the player's first window (the caller makes the player).
    @discardableResult mutating func acquire(_ k: PlayerShareKey, holder: String) -> Bool {
        let first = holders[k] == nil
        if holders[k]?[holder] == nil { holders[k, default: [:]][holder] = false }
        return first
    }

    /// Removes a window. True when it was the player's last window (the caller releases the player).
    @discardableResult mutating func release(_ k: PlayerShareKey, holder: String) -> Bool {
        guard var h = holders[k], h[holder] != nil else { return false }
        h[holder] = nil
        holders[k] = h.isEmpty ? nil : h
        return h.isEmpty
    }

    /// Records whether this window wants the video running; returns whether the shared player should run now.
    @discardableResult mutating func setWantsRun(_ run: Bool, key k: PlayerShareKey, holder: String) -> Bool {
        if holders[k]?[holder] != nil { holders[k]?[holder] = run }
        return shouldRun(k)
    }
}
