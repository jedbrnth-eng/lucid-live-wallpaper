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
            if UserDefaults.standard.bool(forKey: "lucidCheck") { LucidEngine.setsDesktopPicture = false }
            let store = Store.shared
            store.engine.refresh()
            if UserDefaults.standard.bool(forKey: "lucidCheck") { Task { @MainActor in await DevCheck.run(store) }; return }
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
            let args = UserDefaults.standard
            if args.bool(forKey: "selftest") {
                Task { @MainActor in
                    let r = await store.runSelfTest()
                    if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: Paths.selftest) }
                    NSApp.terminate(nil)
                }
            }
            if let p = args.string(forKey: "applyPath"), FileManager.default.fileExists(atPath: p) {
                let u = URL(fileURLWithPath: p)
                Task { @MainActor in
                    store.importFiles([u])
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let it = store.libraryItem("local:\(Paths.safe(p))") { store.setWallpaper(it) }
                }
            }
            if let id = args.string(forKey: "applyAerial"), let it = store.aerials.first(where: { $0.id == "aerials:\(id)" || $0.title == id }) {
                store.setWallpaper(it)
            }
            if let src = args.string(forKey: "testLoop") {
                Task {
                    let dst = URL(fileURLWithPath: src + ".loop.mp4")
                    do { try await LoopMaker.make(URL(fileURLWithPath: src), to: dst); print("LOOP_OK \(dst.path)") }
                    catch { print("LOOP_FAIL \(error.localizedDescription)") }
                    exit(0)
                }
                return
            }
            if let t = args.string(forKey: "testLive"), let it = store.live.first(where: { $0.id.contains(t) }) ?? store.live.first {
                store.setWallpaper(it)
            }
            if let q = args.string(forKey: "testDownloadWikimedia") {
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
