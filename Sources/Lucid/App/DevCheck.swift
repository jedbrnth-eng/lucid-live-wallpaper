// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Headless integration check for development builds. Runs only with BOTH -lucidCheck YES on the command line and
// LUCID_SUPPORT_DIR set (it refuses to touch your real library), and keeps its settings in a separate defaults suite:
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
            // Four phases: add a dawn wallpaper; at dawn (two-phase still "night") it shows, at dusk without one night stays.
            if let dawnPNG = makePNG(.systemYellow, "check-dawn.png") {
                var four = rule; four.dawn = Assignment(itemID: "check-dawn", title: "Check Dawn", path: dawnPNG.path, kind: .image)
                engine.applyDayNight(four, screenKey: nil)
                engine.part = { .dawn }; engine.phaseDidChange()
                await wait(LucidEngine.crossfade + 0.8)
                r["dn4_dawn_shown"] = engine.surfaces[main.stableKey]?.assignment.itemID
                engine.part = { .dusk }; engine.phaseDidChange()
                await wait(LucidEngine.crossfade + 0.8)
                r["dn4_dusk_without_wallpaper_shows"] = engine.surfaces[main.stableKey]?.assignment.itemID
                engine.part = { .night }
            }
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

            // 3. Smart pausing + memory hygiene: pretend the display slept, jump the clock past the release delay,
            //    check every window/player was released, then wake and check it was rebuilt.
            engine.simulate { $0.asleep = true }
            r["pause_status_asleep"] = engine.statusText
            r["pause_running_while_asleep"] = engine.surfaces.values.contains { $0.isRunning && $0.player != nil }
            let realNow = engine.now
            engine.now = { realNow().addingTimeInterval(Double(max(1, Pref.releaseAfterMinutes)) * 60 + 1) }
            engine.checkIdleRelease()
            engine.now = realNow
            r["pause_parked"] = engine.parked
            r["pause_windows_while_parked"] = engine.surfaces.count
            engine.simulate { $0.asleep = false }
            await wait(0.5)
            r["pause_unparked_windows"] = engine.surfaces.count
            r["pause_status_awake"] = engine.statusText
            engine.clear(screenKey: nil)
            await wait(0.3)
            r["windows_after_clear"] = engine.surfaces.count
        }
        await importChecks(store, &r)
        renderViews(store, &r)
        await weatherChecks(store, &r)
        await reviewChecks(store, &r)
        // 6. Global shortcuts (dev bundle's own defaults): enable, check all three registered, a second claim of the
        //    same combination is refused by macOS, then turn them off again.
        let hk = HotkeyCenter.shared
        var b = HotkeyBindings.defaults; b.enabled = true
        hk.update(b)
        r["hotkeys_registered"] = hk.registeredCount
        r["hotkeys_problems"] = hk.problems.map { "\($0.key.rawValue): \($0.value)" }
        if let k = b.binding(.next) { r["hotkeys_second_claim_status"] = Int(HotkeyCenter.probe(k)) }
        var off = b; off.enabled = false
        hk.update(off)
        r["hotkeys_registered_after_off"] = hk.registeredCount
        r["phase_now"] = store.dayNight.phase.rawValue
        r["next_change"] = store.dayNight.nextChange.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
        r["day_night_source"] = store.dayNight.sourceText
        finish(r)
    }

    /// 4. Import: a good photo is accepted, a program renamed .mp4, an empty file, a damaged video and a symlink out of
    ///    the chosen folder are refused; per-wallpaper fit/focus reaches the on-screen layer.
    private static func importChecks(_ store: Store, _ r: inout [String: Any]) async {
        let fm = FileManager.default
        let dir = Paths.support.appendingPathComponent("import-check", isDirectory: true)
        try? fm.removeItem(at: dir); try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let png = makePNG(.systemTeal, "import-check/Good Photo.png") else { r["import_error"] = "png"; return }
        try? Data([0x4D, 0x5A, 0x90, 0, 3, 0, 0, 0, 4, 0, 0, 0, 0xFF, 0xFF, 0, 0]).write(to: dir.appendingPathComponent("evil.mp4"))
        try? Data().write(to: dir.appendingPathComponent("empty.jpg"))
        try? Data([0, 0, 0, 0x18] + Array("ftypmp42".utf8) + [UInt8](repeating: 0x41, count: 4096)).write(to: dir.appendingPathComponent("damaged.mp4"))
        func label(_ x: Store.ImportResult) -> String {
            switch x { case .added: return "added"; case .duplicate: return "duplicate"; case .unsupported: return "unsupported"; case .failed(let m): return "failed: \(m)" }
        }
        r["import_good_png"] = label(await store.importOne(png, move: false, site: nil, page: nil))
        r["import_evil_mp4"] = label(await store.importOne(dir.appendingPathComponent("evil.mp4"), move: false, site: nil, page: nil))
        r["import_empty_jpg"] = label(await store.importOne(dir.appendingPathComponent("empty.jpg"), move: false, site: nil, page: nil))
        r["import_damaged_mp4"] = label(await store.importOne(dir.appendingPathComponent("damaged.mp4"), move: false, site: nil, page: nil))
        if let w = ProcessInfo.processInfo.environment["LUCID_CHECK_WEBM"] {   // optional: a real WebM to convert (needs ffmpeg)
            r["import_webm"] = label(await store.importOne(URL(fileURLWithPath: w), move: false, site: nil, page: nil))
            r["import_webm_converted"] = store.library.first { $0.title == Importer.niceTitle(URL(fileURLWithPath: w).deletingPathExtension().lastPathComponent) }?.fileExt ?? NSNull()
        }
        let copied = store.library.first { $0.title == "Good Photo" }
        r["import_copy_in_media"] = copied?.localPath.map { ImportPolicy.isContained($0, in: Paths.media.path) } ?? false
        r["import_copy_name"] = copied?.localPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? NSNull()
        // Per-wallpaper options: stretch, then fill with top focus, on a reactive image surface (forces a window)
        if let it = copied, let main = NSScreen.screens.first {
            store.setWallpaper(it)
            store.engine.setReactive(ReactiveOptions(glow: true), for: main)
            await wait(0.5)
            store.setOptions(it, WallpaperOptions(fit: .stretch))
            await wait(0.3)
            if let h = store.engine.surfaces[main.stableKey]?.host {
                h.layoutSubtreeIfNeeded()
                r["options_stretch_frame_equals_screen"] = h.contentLayer.bounds.size == h.bounds.size
                store.setOptions(it, WallpaperOptions(fit: .fill, focusY: 0))
                await wait(0.3); h.layoutSubtreeIfNeeded()
                r["options_fill_top_maxY_equals_screen"] = abs(h.contentLayer.frame.maxY - h.bounds.maxY) < 1
                r["options_saved"] = store.libraryItem(it.id)?.options == WallpaperOptions(fit: .fill, focusY: 0)
            } else { r["options_error"] = "no surface" }
            store.engine.clear(screenKey: nil)
        }
        await playlistChecks(store, &r)
    }

    /// 5. Playlists: play two stills on all displays, check they get a window (for the cross-fade), next/previous,
    ///    a due timer catching up, and the run surviving a reload of playback.json.
    private static func playlistChecks(_ store: Store, _ r: inout [String: Any]) async {
        guard let u = makePNG(.systemPink, "import-check/Second Photo.png") else { return }
        _ = await store.importOne(u, move: false, site: nil, page: nil)
        let items = store.library.filter { $0.title == "Good Photo" || $0.title == "Second Photo" }
        guard items.count == 2, let main = NSScreen.screens.first else { r["playlist_error"] = "items \(items.count)"; return }
        let p = store.createPlaylist("Check Mix")
        var pl = p; pl.items = items; pl.shuffle = false; pl.minutes = 60
        store.updatePlaylist(pl)
        store.playPlaylist(p.id)
        await wait(LucidEngine.crossfade + 0.5)
        let first = store.engine.surfaces[main.stableKey]?.assignment.itemID
        r["playlist_first_on_screen"] = first == items[0].id
        r["playlist_still_has_window"] = store.engine.surfaces[main.stableKey] != nil
        store.next()
        await wait(LucidEngine.crossfade + 0.5)
        r["playlist_next_on_screen"] = store.engine.surfaces[main.stableKey]?.assignment.itemID == items[1].id
        store.previous()
        await wait(0.3)
        r["playlist_previous_on_screen"] = store.engine.currentAssignments.first?.itemID == items[0].id
        store.playlistTick(now: Date().addingTimeInterval(3601))
        await wait(0.3)
        r["playlist_due_tick_advanced"] = store.engine.currentAssignments.first?.itemID == items[1].id
        if let d = try? Data(contentsOf: Paths.playback) {
            r["playlist_resume_saved"] = PlaybackState.decode(d).runs[EngineState.allKey] == store.runs[EngineState.allKey]
        }
        // A wallpaper set on one display while an all-displays playlist plays must survive the playlist's next change.
        store.setWallpaper(items[0], screenKey: main.stableKey)
        store.playlistTick(now: Date().addingTimeInterval(3601 * 3))
        await wait(0.3)
        r["review_l3_per_display_kept_after_tick"] = store.engine.state.perScreen[main.stableKey] != nil
        store.stopPlaylist()
        store.engine.clear(screenKey: nil)
        await wait(0.3)
        r["playlist_windows_after_stop"] = store.engine.surfaces.count
    }

    /// 7. Weather: a rain wallpaper overrides while it "rains", the normal one returns when clear, a stale reading
    ///    is ignored, and an unreachable server fails quietly with back-off (no real weather request is made unless
    ///    LUCID_CHECK_NETWORK=1, which also does one live Open-Meteo fetch).
    private static func weatherChecks(_ store: Store, _ r: inout [String: Any]) async {
        let e = store.engine
        guard let main = NSScreen.screens.first, let base = makePNG(.systemGray, "check-base.png"), let wet = makePNG(.systemBlue, "check-rain.png") else { return }
        let normal = Assignment(itemID: "check-base", title: "Base", path: base.path, kind: .image)
        let rainA = Assignment(itemID: "check-rain", title: "Rain", path: wet.path, kind: .image)
        e.apply(normal, screenKey: nil)
        e.setWeather(WeatherRule(map: [.rain: rainA]), screenKey: nil)
        let real = e.weatherNow
        e.weatherNow = { .rain }; e.weatherDidChange()
        await wait(LucidEngine.crossfade + 0.6)
        r["weather_rain_shows"] = e.surfaces[main.stableKey]?.assignment.itemID ?? NSNull()
        e.weatherNow = { .clear }; e.weatherDidChange()
        await wait(LucidEngine.crossfade + 0.6)
        r["weather_clear_shows"] = e.assignment(for: main)?.itemID ?? NSNull()
        e.weatherNow = real
        r["weather_stale_or_off_condition"] = store.weather.activeCondition?.rawValue ?? "none"
        if let bad = URL(string: "https://127.0.0.1:9/v1/forecast") {
            let before = store.weather.fetchState.failures
            await store.weather.fetch(url: bad)
            r["weather_offline_failures_added"] = store.weather.fetchState.failures - before
            r["weather_offline_error"] = store.weather.lastError ?? NSNull()
            r["weather_offline_backoff_blocks_retry"] = !WeatherPolicy.shouldFetch(store.weather.fetchState, now: Date())
        }
        if ProcessInfo.processInfo.environment["LUCID_CHECK_NETWORK"] == "1" {
            let (lat, lon) = WeatherService.coordinates()
            let u = WeatherRequest.url(latitude: lat, longitude: lon)
            r["weather_live_url"] = u.absoluteString
            await store.weather.fetch(url: u)
            r["weather_live_condition"] = store.weather.condition?.rawValue ?? NSNull()
            r["weather_live_error"] = store.weather.lastError ?? NSNull()
            Pref.updateCheck = true
            UpdateChecker.shared.checkIfDue(force: true)
            for _ in 0..<40 where UpdateChecker.shared.status == "Checking…" { await wait(0.25) }
            r["update_check_live_status"] = UpdateChecker.shared.status
            Pref.updateCheck = false
        }
        e.setWeather(WeatherRule(map: [:]), screenKey: nil)
        e.clear(screenKey: nil)
        await wait(0.3)
    }

    /// 9. Regressions from the 1.3.0 review: what remove() may delete, symlinks and same-name/same-size files on a
    ///    moving import, two imports of one file at once, a late video poster, and windows after rapid changes.
    private static func reviewChecks(_ store: Store, _ r: inout [String: Any]) async {
        let fm = FileManager.default, e = store.engine
        let dir = Paths.support.appendingPathComponent("review-check", isDirectory: true)
        try? fm.removeItem(at: dir)
        for s in ["a", "b", "victim"] { try? fm.createDirectory(at: dir.appendingPathComponent(s), withIntermediateDirectories: true) }
        func label(_ x: Store.ImportResult) -> String {
            switch x { case .added: return "added"; case .duplicate: return "duplicate"; case .unsupported: return "unsupported"; case .failed(let m): return "failed: \(m)" }
        }
        // H1: a library entry whose thumbnail is a file elsewhere, and whose path is a link (outside Media) into Media.
        if let img = makePNG(.systemGreen, "review-check/a/Victim Photo.png") {
            _ = await store.importOne(img, move: false, site: nil, page: nil)
            if var it = store.library.first(where: { $0.title == "Victim Photo" }), let real = it.localPath {
                let victim = dir.appendingPathComponent("victim/notes.txt"), link = dir.appendingPathComponent("victim/link-into-media.png")
                try? Data("keep me".utf8).write(to: victim)
                try? fm.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: real))
                it.thumbPath = victim.path; it.localPath = link.path
                store.addToLibrary(it)
                store.remove(it)
                r["review_h1_outside_thumb_kept"] = fm.fileExists(atPath: victim.path)
                r["review_h1_outside_link_kept"] = (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil
            }
        }
        // H2: a link dropped where Lucid moves files in must not move or delete what it points to.
        if let secret = makePNG(.systemRed, "review-check/victim/Secret.png") {
            let link = dir.appendingPathComponent("a/Linked.png")
            try? fm.createSymbolicLink(at: link, withDestinationURL: secret)
            r["review_h2_move_symlink_result"] = label(await store.importOne(link, move: true, site: nil, page: nil))
            r["review_h2_move_symlink_target_kept"] = fm.fileExists(atPath: secret.path)
        }
        // H2: a different photo with the same name and size is added, not deleted as a "duplicate".
        if let a = makePNG(.systemOrange, "review-check/a/Same.png"), let b = makePNG(.systemPurple, "review-check/b/Same.png") {
            for u in [a, b] { if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); let n = 8192 - Int(h.offsetInFile); if n > 0 { h.write(Data(count: n)) }; try? h.close() } }
            let sizes = [a, b].map { (try? fm.attributesOfItem(atPath: $0.path)[.size] as? Int) ?? -1 }
            r["review_h2_same_size"] = sizes[0] == sizes[1]
            _ = await store.importOne(a, move: false, site: nil, page: nil)
            r["review_h2_collision_result"] = label(await store.importOne(b, move: true, site: nil, page: nil))
            r["review_h2_collision_items"] = store.library.filter { $0.title == "Same" }.count
            try? fm.removeItem(at: b); try? fm.copyItem(at: a, to: b)   // an identical copy is a real duplicate
            r["review_h2_identical_result"] = label(await store.importOne(b, move: true, site: nil, page: nil))
            r["review_h2_collision_items_after_identical"] = store.library.filter { $0.title == "Same" }.count
        }
        // M4: the same new file imported twice at once.
        if let t = makePNG(.systemBrown, "review-check/a/Twice.png") {
            async let x = store.importOne(t, move: false, site: nil, page: nil)
            async let y = store.importOne(t, move: false, site: nil, page: nil)
            r["review_m4_concurrent_same_file"] = [label(await x), label(await y)].sorted().joined(separator: ",")
        }
        // M4: a video's poster finishing after a newer wallpaper was set must not replace it as the desktop picture.
        if let v = ProcessInfo.processInfo.environment["LUCID_CHECK_VIDEO"], let still = makePNG(.systemMint, "review-check/still.png"),
           let main = NSScreen.screens.first {
            var calls: [String] = []
            LucidEngine.desktopHook = { url, s in if s.stableKey == main.stableKey { calls.append(url.lastPathComponent) } }
            e.apply(Assignment(itemID: "review-video", title: "Video", path: v, kind: .video), screenKey: nil)
            e.apply(Assignment(itemID: "review-still", title: "Still", path: still.path, kind: .image), screenKey: nil)
            await wait(5)
            r["review_m4_desktop_last_is_current"] = calls.last == still.lastPathComponent
            r["review_m4_desktop_calls"] = calls.joined(separator: ",")
            LucidEngine.desktopHook = nil
            e.clear(screenKey: nil)
        }
        // M5: three changes inside one cross-fade, then clear: no window may be left behind.
        let pics = [NSColor.systemRed, .systemGreen, .systemBlue].enumerated().compactMap { makePNG($0.element, "review-check/fade\($0.offset).png") }
        if pics.count == 3 {
            let looks = pics.enumerated().map { Assignment(itemID: "fade\($0.offset)", title: "Fade", path: $0.element.path, kind: .image, reactive: ReactiveOptions(glow: true)) }
            e.apply(looks[0], screenKey: nil); await wait(0.5)
            e.apply(looks[1], screenKey: nil); await wait(0.2)
            e.apply(looks[2], screenKey: nil)
            e.clear(screenKey: nil)
            await wait(LucidEngine.crossfade + 1.5)
            r["review_m5_fading_after_clear"] = e.fadingCount
            r["review_m5_wallpaper_windows_after_clear"] = NSApp.windows.filter { $0 is WallpaperWindow && $0.isVisible }.count
        }
        // L1: turning location off forgets the saved fix.
        Pref.dayNightUseLocation = true
        Pref.lastLocation = (13.7563, 100.5018)
        Pref.dayNightUseLocation = false
        r["review_l1_location_cleared_when_off"] = Pref.lastLocation == nil
    }

    /// 8. Render every screen of the app off-screen with the shared environment, so a view that reads an
    ///    environment object nobody provides crashes here (in the check) instead of in front of a user.
    private static func renderViews(_ store: Store, _ r: inout [String: Any]) {
        func render<V: View>(_ name: String, _ v: V) -> String {
            let host = NSHostingView(rootView: v.lucidEnvironment(store).frame(width: 1100, height: 800))
            host.frame = NSRect(x: 0, y: 0, width: 1100, height: 800)
            host.layoutSubtreeIfNeeded()
            _ = host.fittingSize
            return "rendered"
        }
        r["render_settings"] = render("settings", ScrollView { SettingsView() })
        if let dir = ProcessInfo.processInfo.environment["LUCID_CHECK_SHOTS"] { shots(store, URL(fileURLWithPath: dir, isDirectory: true), &r) }
        r["render_displays"] = render("displays", DisplaysView())
        r["render_menu"] = render("menu", VStack { MenuContent() })
        r["render_library"] = render("library", LibraryView(mode: .downloaded))
        if let it = store.library.first { r["render_detail"] = render("detail", DetailView(item: it)) }
        if let w = NSScreen.screens.first {
            r["render_weather_sheet"] = render("weather", WeatherSheet(target: DNTarget(screenKey: nil, name: w.localizedName)))
            r["render_daynight_sheet"] = render("daynight", DayNightSheet(target: DNTarget(screenKey: nil, name: w.localizedName)))
        }
    }

    /// Optional (LUCID_CHECK_SHOTS=<dir>): PNGs of the new screens, rendered off-screen with real app state.
    private static func shots(_ store: Store, _ dir: URL, _ r: inout [String: Any]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Real state for the pictures: a Day/Night rule with a dawn wallpaper, a weather rule, a playing playlist.
        if let p = store.playlists.first { store.playPlaylist(p.id) }
        let imgs = store.library.filter { $0.kind == .image && $0.isLocalReady }
        if imgs.count >= 3, let d = store.readyAssignment(for: imgs[0]), let n = store.readyAssignment(for: imgs[1]), let a = store.readyAssignment(for: imgs[2]) {
            store.engine.applyDayNight(DayNightRule(day: d, night: n, dawn: a), screenKey: NSScreen.screens.first?.stableKey)
            store.engine.setWeather(WeatherRule(map: [.rain: a, .snow: n]), screenKey: nil)
        }
        defer { store.stopPlaylist(); store.engine.setWeather(WeatherRule(map: [:]), screenKey: nil); store.engine.clear(screenKey: nil) }
        func shot<V: View>(_ name: String, _ v: V, width: CGFloat, height: CGFloat? = nil) {
            let root = v.lucidEnvironment(store).preferredColorScheme(.dark).frame(width: width).background(Color(white: 0.11))
            let host = NSHostingView(rootView: root)
            let size = NSSize(width: width, height: height ?? min(4000, max(200, host.fittingSize.height)))
            let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            win.appearance = NSAppearance(named: .darkAqua)
            win.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent(name + ".png"))
                r["shot_" + name] = "\(Int(size.width))x\(Int(size.height))"
            }
            win.contentView = nil
        }
        shot("settings-full", SettingsView().padding(24), width: 640)
        shot("displays", DisplaysView(), width: 1100, height: 760)
        if let w = NSScreen.screens.first {
            shot("weather-sheet", WeatherSheet(target: DNTarget(screenKey: nil, name: "All Displays")), width: 540)
            shot("daynight-sheet", DayNightSheet(target: DNTarget(screenKey: w.stableKey, name: w.localizedName)), width: 540)
        }
        if let p = store.playlists.first { shot("playlist", PlaylistView(id: p.id), width: 1100, height: 520) }
        if let it = store.library.first(where: { $0.kind == .video }) ?? store.library.first { shot("detail-options", DetailView(item: it), width: 820) }
        shot("library", LibraryView(mode: .downloaded), width: 1100, height: 700)
        shot("menu-bar-menu", VStack(alignment: .leading, spacing: 6) { MenuContent() }.padding(12), width: 360)
    }

    private static func finish(_ r: [String: Any]) {
        let u = Paths.support.appendingPathComponent("check.json")
        if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: u) }
        NSApp.terminate(nil)
    }
}
