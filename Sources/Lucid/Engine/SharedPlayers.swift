// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// The looping video players behind the wallpaper windows. A video shown on several displays at the same speed is
// decoded once: every display's AVPlayerLayer shows the same player (bookkeeping in PlayerShare.swift).
// Same idea as the Aerial screen saver's mirrored mode (one player, a layer per screen).
import AVFoundation

@MainActor final class SharedPlayers {
    static let shared = SharedPlayers()
    private var share = PlayerShare()
    private var loops: [PlayerShareKey: (player: AVQueuePlayer, looper: AVPlayerLooper)] = [:]

    /// Players alive right now (status file and benchmark).
    var count: Int { loops.count }

    /// The looping, muted player for this file at this speed; made on first use. `holder` is one wallpaper window.
    func acquire(path: String, speed: Double, holder: String) -> AVQueuePlayer {
        let k = PlayerShareKey(path: path, speed: speed)
        share.acquire(k, holder: holder)
        if let l = loops[k] { return l.player }
        let p = AVQueuePlayer()
        p.isMuted = true
        p.preventsDisplaySleepDuringVideoPlayback = false
        p.automaticallyWaitsToMinimizeStalling = false
        let item = AVPlayerItem(url: URL(fileURLWithPath: path))
        item.preferredForwardBufferDuration = 2
        let looper = AVPlayerLooper(player: p, templateItem: item)
        p.defaultRate = Float(speed)
        loops[k] = (p, looper)
        return p
    }

    /// One window wants the video running or paused; the player runs while any of its windows wants it.
    func setRunning(_ run: Bool, path: String, speed: Double, holder: String) {
        let k = PlayerShareKey(path: path, speed: speed)
        guard let p = loops[k]?.player else { return }
        apply(share.setWantsRun(run, key: k, holder: holder), p, speed)
    }

    /// A window closed. The player stops with its last window; until then it keeps running for the others.
    func release(path: String, speed: Double, holder: String) {
        let k = PlayerShareKey(path: path, speed: speed)
        if share.release(k, holder: holder), let l = loops.removeValue(forKey: k) {
            l.player.pause()
            l.looper.disableLooping()
            l.player.removeAllItems()
        } else if let p = loops[k]?.player {
            apply(share.shouldRun(k), p, speed)
        }
    }

    private func apply(_ run: Bool, _ p: AVQueuePlayer, _ speed: Double) {
        let r = Float(speed)
        if run { if p.rate != r { p.defaultRate = r; p.rate = r } } else if p.rate != 0 { p.pause() }
    }
}
