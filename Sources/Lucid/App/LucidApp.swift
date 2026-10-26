// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// App entry point, delegate, menu bar item and file import.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ app: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { Store.shared.importFiles(urls); NSApp.activate(ignoringOtherApps: true) }
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        MainActor.assumeIsolated {
            if DevMode.checkRequested && !DevMode.check {
                FileHandle.standardError.write(Data("lucidCheck needs LUCID_SUPPORT_DIR (a throwaway folder); refusing to run it on your library.\n".utf8))
                exit(2)
            }
            if DevMode.check { LucidEngine.setsDesktopPicture = false }
            let store = Store.shared
            store.engine.refresh()
            if DevMode.check { Task { @MainActor in await DevCheck.run(store) }; return }
            store.startDownloadsWatcher()
            HotkeyCenter.shared.handler = { action in
                switch action {
                case .pauseResume: store.engine.togglePause()
                case .next: store.next()
                case .previous: store.previous()
                }
            }
            HotkeyCenter.shared.apply()
            UpdateChecker.shared.start()
            // Test hooks below come from this launch's arguments only (DevMode), never from saved preferences.
            if DevMode.flag("selftest") {
                Task { @MainActor in
                    let r = await store.runSelfTest()
                    if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: Paths.selftest) }
                    NSApp.terminate(nil)
                }
            }
            if let p = DevMode.arg("applyPath"), FileManager.default.fileExists(atPath: p) {
                let u = URL(fileURLWithPath: p)
                Task { @MainActor in
                    store.importFiles([u])
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let it = store.libraryItem("local:\(Paths.safe(p))") { store.setWallpaper(it) }
                }
            }
            if let id = DevMode.arg("applyAerial"), let it = store.aerials.first(where: { $0.id == "aerials:\(id)" || $0.title == id }) {
                store.setWallpaper(it)
            }
            if let src = DevMode.arg("testLoop") {
                Task {
                    let dst = URL(fileURLWithPath: src + ".loop.mp4")
                    do { try await LoopMaker.make(URL(fileURLWithPath: src), to: dst); print("LOOP_OK \(dst.path)") }
                    catch { print("LOOP_FAIL \(error.localizedDescription)") }
                    exit(0)
                }
                return
            }
            // Development: download one URL through the real Downloader, print each step, then what is left in Media/.
            // `-testDownloadCancelAt Converting` cancels 2 s into the step whose text starts with that word;
            // `-testConversionTimeout 3` shortens the per-step limit to test the timeout.
            if let s = DevMode.arg("testDownloadURL"), let u = URL(string: s) {
                setvbuf(stdout, nil, _IOLBF, 0)
                var it = WallItem(id: "test:dl-" + Paths.safe(u.lastPathComponent), source: Source(rawValue: DevMode.arg("testDownloadSource") ?? "") ?? .wikimedia,
                                  kind: ImportPolicy.kind(forExtension: u.pathExtension.lowercased()) ?? .video, title: "Download test", width: 3840, height: 2160)
                it.downloadURL = s
                let t0 = Date(), cancelAt = DevMode.arg("testDownloadCancelAt")
                let dl = store.downloader
                if let t = DevMode.arg("testConversionTimeout").flatMap(Double.init) { dl.conversionTimeout = t }
                Downloader.phaseHook = { id, p in
                    print(String(format: "PHASE %6.1f s  %@", Date().timeIntervalSince(t0), p.label))
                    if let c = cancelAt, p.label.hasPrefix(c) {
                        Task { @MainActor in try? await Task.sleep(nanoseconds: 2_000_000_000); print("CANCEL"); dl.cancel(id) }
                    }
                }
                store.download(it)
                Task { @MainActor in
                    while dl.progress[it.id] != nil { try? await Task.sleep(nanoseconds: 250_000_000) }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)   // let a cancelled step delete its files
                    print(String(format: "END %6.1f s", Date().timeIntervalSince(t0)))
                    print("ERROR \(dl.errors[it.id] ?? "none") retry=\(dl.canRetry(it.id))")
                    print("LIBRARY \(store.libraryItem(it.id).map { "\($0.localPath ?? "-") \($0.width)x\($0.height) \($0.codec ?? "-")" } ?? "none")")
                    let left = (try? FileManager.default.contentsOfDirectory(atPath: Paths.media.path)) ?? []
                    print("MEDIA \(left.sorted().joined(separator: ", "))")
                    exit(0)
                }
                return
            }
            if let t = DevMode.arg("testLive"), let it = store.live.first(where: { $0.id.contains(t) }) ?? store.live.first {
                store.setWallpaper(it)
            }
            if let q = DevMode.arg("testDownloadWikimedia") {
                Task { @MainActor in
                    if let r = try? await Providers.wikimedia(q, offset: 0, featured: true), let first = r.items.first {
                        store.setWallpaper(first)
                    }
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
}

@main
struct LucidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        Window("Lucid", id: "main") {
            ContentView().lucidEnvironment(store)
                .frame(minWidth: 1020, minHeight: 660)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1240, height: 800)
        Settings {
            ScrollView {
                SettingsView().frame(width: 560).padding(20)
            }
            .frame(minHeight: 480, idealHeight: 760)
            .lucidEnvironment(store)
            .preferredColorScheme(.dark)
        }
        MenuBarExtra("Lucid", systemImage: "sparkles.tv") {
            MenuContent().lucidEnvironment(store)
        }
    }
}

extension View {
    /// Every shared object any Lucid view may read. One list for all windows (a missing one crashes SwiftUI at runtime).
    @MainActor func lucidEnvironment(_ store: Store) -> some View {
        environmentObject(store).environmentObject(store.engine).environmentObject(store.downloader)
            .environmentObject(store.audio).environmentObject(store.dayNight).environmentObject(store.weather)
            .environmentObject(HotkeyCenter.shared)
    }
}

// MARK: - Import helpers

enum Importer {
    /// "kratos-atreus-winter-hunt.3840x2160" -> "Kratos Atreus Winter Hunt"
    static func niceTitle(_ base: String) -> String {
        var t = base
        t = t.replacingOccurrences(of: #"[._ -]?(\d{3,4}x\d{3,4}|4k|uhd|2160p|hd|1080p)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"[-_.]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if t.isEmpty { t = base }
        return t.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
