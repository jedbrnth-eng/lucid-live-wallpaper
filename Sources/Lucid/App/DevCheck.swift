// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Headless integration check for development builds (off unless you pass -lucidCheck YES):
//   LUCID_SUPPORT_DIR=/tmp/lucid-check Lucid.app/Contents/MacOS/Lucid -lucidCheck YES
// Sets a Day/Night pair of generated images, flips the phase, checks the cross-fade released the old window,
// then feeds synthetic bass to an audio-reactive look. Writes check.json and quits.
// Never starts audio capture and never changes the real desktop picture.
import SwiftUI
import AppKit

@MainActor enum DevCheck {
    private static func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    private static func makePNG(_ color: NSColor, _ name: String) -> URL? {
        let u = Paths.support.appendingPathComponent(name)
        let w = 320, h = 180
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(color.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        guard let img = ctx.makeImage(), let d = CGImageDestinationCreateWithURL(u as CFURL, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(d, img, nil)
        return CGImageDestinationFinalize(d) ? u : nil
    }

    static func run(_ store: Store) async {
        var r: [String: Any] = ["support": Paths.support.path]
        let engine = store.engine
        guard let main = NSScreen.screens.first else { r["error"] = "no screen"; finish(r); return }

        // 1. Day/Night with generated images, then flip the phase and check the cross-fade released the old window
        if let day = makePNG(.systemOrange, "check-day.png"), let night = makePNG(.systemIndigo, "check-night.png") {
            let rule = DayNightRule(day: Assignment(itemID: "check-day", title: "Check Day", path: day.path, kind: .image),
                                    night: Assignment(itemID: "check-night", title: "Check Night", path: night.path, kind: .image))
            engine.phase = { .day }
            engine.applyDayNight(rule, screenKey: nil)
            await wait(2)
            r["dn_day_shown"] = engine.surfaces[main.stableKey]?.assignment.itemID
            engine.phase = { .night }
            engine.phaseDidChange()
            await wait(0.3)
            r["dn_fading_during"] = engine.surfaces.count > 0
            await wait(LucidEngine.crossfade + 1)
            r["dn_night_shown"] = engine.surfaces[main.stableKey]?.assignment.itemID
            if let d = try? Data(contentsOf: Paths.state), let st = try? JSONDecoder().decode(EngineState.self, from: d) {
                r["dn_persisted"] = st.dayNight?[EngineState.allKey] != nil
            }

            // 2. Audio-reactive look on the image surface (synthetic bass, no capture)
            engine.setReactive(ReactiveOptions(pulse: true, glow: true, bars: true), for: main)
            await wait(0.3)
            let bass = AudioAnalyser(sampleRate: 48_000).analyse(left: (0..<4096).map { Float(sin(2 * Double.pi * 70 * Double($0) / 48_000)) }, right: nil)
            engine.deliverAudio(bass)
            if let h = engine.surfaces[main.stableKey]?.host {
                r["reactive_scale"] = h.contentLayer.transform.m11
                r["reactive_glow"] = h.glowLayer.opacity
                r["reactive_bars_visible"] = !h.barsLayer.isHidden
            }
            r["audio_status"] = store.audio.status.text
            engine.clear(screenKey: nil)
            await wait(0.3)
            r["windows_after_clear"] = engine.surfaces.count
        }
        r["phase_now"] = store.dayNight.phase.rawValue
        r["next_change"] = store.dayNight.nextChange.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
        r["day_night_source"] = store.dayNight.sourceText
        finish(r)
    }

    private static func finish(_ r: [String: Any]) {
        let u = Paths.support.appendingPathComponent("check.json")
        if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: u) }
        NSApp.terminate(nil)
    }
}
