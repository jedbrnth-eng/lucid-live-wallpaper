// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Headless integration check for development builds:
//   LUCID_SUPPORT_DIR=/tmp/lucid-check Lucid.app/Contents/MacOS/Lucid -lucidCheck YES -weFolder <fixtures folder>
// Links a Wallpaper Engine folder, applies a web wallpaper and feeds it synthetic audio, sets a Day/Night pair
// of generated images, flips the phase, and checks the reactive look. Writes check.json and quits.
// Never starts audio capture and never changes the real desktop picture.
import SwiftUI
import AppKit
import WebKit

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

    private static func js(_ wv: WKWebView, _ s: String) async -> Any? {
        await withCheckedContinuation { c in wv.evaluateJavaScript(s) { v, _ in c.resume(returning: v) } }
    }

    static func run(_ store: Store) async {
        var r: [String: Any] = ["support": Paths.support.path]
        let engine = store.engine
        guard let main = NSScreen.screens.first else { r["error"] = "no screen"; finish(r); return }

        // 1. Wallpaper Engine sync
        if let f = UserDefaults.standard.string(forKey: "weFolder") {
            store.we.addFolder(URL(fileURLWithPath: f))
            for _ in 0..<40 { await wait(0.25); if !store.we.scanning && store.we.lastScan != nil { break } }
            r["we_counts"] = ["video": store.we.counts.video, "web": store.we.counts.web, "unsupported": store.we.counts.unsupported]
            r["we_errors"] = store.we.errors
            r["we_items"] = store.we.items.map { "\($0.id) [\($0.weSupport?.rawValue ?? "?")] \($0.title)" }

            // 2. Web wallpaper with the WE shim + synthetic audio
            if let web = store.we.items.first(where: { $0.weSupport == .web }) {
                store.setWallpaper(web)
                for _ in 0..<20 { await wait(0.25); if engine.surfaces[main.stableKey]?.web != nil { break } }
                await wait(2.5)
                if let s = engine.surfaces[main.stableKey], let wv = s.web {
                    r["web_surface"] = true
                    r["web_shim"] = await js(wv, "typeof window.wallpaperRegisterAudioListener + '/' + (window.__lucidShim === true)")
                    r["web_props"] = await js(wv, "window.__gotProps || null")
                    let tone = AudioAnalyser(sampleRate: 48_000).analyse(left: (0..<4096).map { Float(sin(2 * Double.pi * 440 * Double($0) / 48_000)) }, right: nil)
                    engine.deliverAudio(tone)
                    await wait(0.5)
                    r["web_audio_len"] = await js(wv, "window.__gotAudio || 0")
                    r["web_audio_peak"] = await js(wv, "window.__audioPeak || 0")
                    r["audio_needed_for_web"] = engine.audioNeeded
                } else { r["web_surface"] = false }
            }
            // 3. Unsupported scene refuses honestly (no window change)
            if let scene = store.we.items.first(where: { $0.category == "Scene" }) {
                let before = engine.surfaces[main.stableKey]?.assignment.path
                store.setWallpaper(scene)
                await wait(0.5)
                r["scene_refused"] = engine.surfaces[main.stableKey]?.assignment.path == before
            }
            // 3b. Video items: native MP4 plays as-is, WebM is converted once and cached (only meaningful with real media files)
            for (key, id) in [("we_mp4", "we:1001"), ("we_webm", "we:1002")] {
                guard let v = store.we.items.first(where: { $0.id == id }) else { continue }
                store.setWallpaper(v)
                var row: [String: Any] = [:]
                for _ in 0..<80 { await wait(0.25); if let s = engine.surfaces[main.stableKey], s.assignment.itemID == id, s.isRunning { break } }
                await wait(WallpaperEngine.crossfade + 0.5)
                if let s = engine.surfaces[main.stableKey], s.assignment.itemID == id {
                    row["playing"] = s.isRunning
                    row["path"] = s.assignment.path
                    row["time"] = s.player?.currentTime().seconds ?? -1
                } else { row["playing"] = false }
                row["windows"] = engine.surfaces.count
                r[key] = row
            }
            // 3c. Live sync: delete an item folder and add a new one; the FSEvents watcher should pick both up
            let root = URL(fileURLWithPath: f)
            let gone = root.appendingPathComponent("workshop/content/431960/1005")
            let added = root.appendingPathComponent("myprojects/added-later")
            if FileManager.default.fileExists(atPath: gone.path) {
                let before = store.we.items.count
                try? FileManager.default.removeItem(at: gone)
                try? FileManager.default.createDirectory(at: added, withIntermediateDirectories: true)
                try? Data(#"{"type":"web","file":"index.html","title":"Added Later"}"#.utf8).write(to: added.appendingPathComponent("project.json"))
                try? Data("<html></html>".utf8).write(to: added.appendingPathComponent("index.html"))
                var ok = false
                for _ in 0..<40 {
                    await wait(0.25)
                    let ids = store.we.items.map(\.title)
                    if !ids.contains("Windows App Wallpaper") && ids.contains("Added Later") { ok = true; break }
                }
                r["we_live_sync"] = ["ok": ok, "before": before, "after": store.we.items.count]
            }
        }

        // 4. Day/Night with generated images, then flip the phase and check the cross-fade released the old window
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
            await wait(WallpaperEngine.crossfade + 1)
            r["dn_night_shown"] = engine.surfaces[main.stableKey]?.assignment.itemID
            if let d = try? Data(contentsOf: Paths.state), let st = try? JSONDecoder().decode(EngineState.self, from: d) {
                r["dn_persisted"] = st.dayNight?[EngineState.allKey] != nil
            }

            // 5. Audio-reactive look on the image surface (synthetic bass, no capture)
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
