// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Turns system-audio capture on only while it is useful: the Settings toggle is on AND a visible, playing
// wallpaper reacts to sound (an "Audio reactive" look or a Wallpaper Engine web page). Otherwise capture is
// fully stopped, following the same pause rules as video (locked, asleep, battery, Low Power, covered).
import Foundation
import SwiftUI

@MainActor final class AudioReactive: ObservableObject {
    enum Status: Equatable {
        case off              // toggle is off
        case idle             // on, but no reactive wallpaper is showing (capture stopped)
        case running
        case noSound          // capturing, but only silence for a while (nothing playing, or permission denied)
        case unavailable(String)
        case failed(String)

        var text: String {
            switch self {
            case .off: return "Off"
            case .idle: return "Waiting: no audio-reactive wallpaper is showing, so nothing is captured"
            case .running: return "Listening to system audio"
            case .noSound: return "No sound detected. If music is playing, allow Lucid in System Settings › Privacy & Security › Screen & System Audio Recording (System Audio Recording Only)"
            case .unavailable(let s), .failed(let s): return s
            }
        }
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var level: Float = 0
    private weak var engine: WallpaperEngine?
    private var tap: AnyObject?
    private var timer: Timer?
    private var analyser: AudioAnalyser?
    private var smoother = AudioSmoother(attack: 0.55, release: 0.12)
    private var silentSince: Date?
    private var needed = false
    static let fps = 30.0

    init(engine: WallpaperEngine) {
        self.engine = engine
        engine.onAudioNeedChanged = { [weak self] n in self?.setNeeded(n) }
        needed = engine.audioNeeded
        reevaluate()
    }

    func setNeeded(_ n: Bool) { needed = n; reevaluate() }

    /// Call after the Settings toggle changes.
    func reevaluate() {
        let want = Pref.audioReactive && needed
        if want && tap == nil { start() }
        else if !want && tap != nil { stop() }
        if !Pref.audioReactive { status = .off }
        else if !want { status = .idle }
    }

    private func start() {
        guard #available(macOS 14.2, *) else { status = .unavailable("Audio reactive needs macOS 14.2 or later"); return }
        let t = SystemAudioTap()
        do {
            try t.start()
        } catch {
            t.stop()
            status = .failed("Couldn't start audio capture: \(error.localizedDescription)")
            return
        }
        tap = t
        analyser = AudioAnalyser(sampleRate: t.sampleRate)
        smoother.reset()
        silentSince = Date()
        status = .running
        timer = Timer.scheduledTimer(withTimeInterval: 1 / Self.fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
    }

    private func frame() {
        guard #available(macOS 14.2, *), let t = tap as? SystemAudioTap, let a = analyser else { return }
        let s = t.snapshot()
        let raw = a.analyse(left: s.left, right: s.right, gain: Float(Pref.audioSensitivity))
        let f = smoother.push(raw)
        level = f.level
        engine?.deliverAudio(f)
        if raw.level > 0.02 { silentSince = nil; if status != .running { status = .running } }
        else if let since = silentSince { if Date().timeIntervalSince(since) > 6 { status = .noSound } }
        else { silentSince = Date() }
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        if #available(macOS 14.2, *) { (tap as? SystemAudioTap)?.stop() }
        tap = nil
        analyser = nil
        level = 0
        engine?.resetAudioLooks()
    }
}
