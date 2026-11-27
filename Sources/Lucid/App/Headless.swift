// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Development runs that must never draw anything: no main window, no menu-bar item, no Dock icon, no desktop
// window and no desktop picture, and no Keychain. The SwiftUI app is never started (see LucidMain), the process
// can't take focus (activation policy .prohibited), wallpaper windows are built but refuse to be ordered in
// (WallpaperWindow) and Keychain reads return nothing. Safe to run while your everyday copy of Lucid plays.
// ./headless-check.sh proves it for the check from outside the app. The integration check (DevCheck.swift):
//   LUCID_SUPPORT_DIR=/tmp/lucid-check build/Lucid.app/Contents/MacOS/Lucid -lucidCheck YES
// It writes check.json in LUCID_SUPPORT_DIR and quits. The playback benchmark:
//   LUCID_SUPPORT_DIR=/tmp/lucid-bench build/Lucid.app/Contents/MacOS/Lucid -lucidBench <video or folder>
//       [-benchDisplays 1,2,3] [-benchSeconds 20] [-benchRounds 3] [-benchHalfSpeed off,on]
// `-lucidBench idle` measures the app itself (store, engine, Day/Night, folder watching) with nothing playing.
// It writes bench.json in LUCID_SUPPORT_DIR and quits. See PlaybackBench.swift for what is measured.
// Screenshots of app screens with a generated demo library (DevShots.swift):
//   LUCID_SUPPORT_DIR=/tmp/lucid-shots build/Lucid.app/Contents/MacOS/Lucid -lucidShots <output folder>
import AppKit

@MainActor enum Headless {
    /// True for the whole run when this launch is a headless one (decided from the command line before anything starts).
    nonisolated static var active: Bool { DevMode.headless }

    static func runCheck() {
        guard DevMode.check else {
            FileHandle.standardError.write(Data("lucidCheck needs LUCID_SUPPORT_DIR (a throwaway folder); refusing to run it on your library.\n".utf8))
            exit(2)
        }
        LucidEngine.setsDesktopPicture = false
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let store = Store.shared
        store.engine.refresh()
        Task { @MainActor in await DevCheck.run(store) }
        app.run()
    }

    static func runBench() {
        guard DevMode.bench, let target = DevMode.arg("lucidBench") else {
            FileHandle.standardError.write(Data("lucidBench needs LUCID_SUPPORT_DIR (a throwaway folder).\n".utf8))
            exit(2)
        }
        LucidEngine.setsDesktopPicture = false
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let displays = (DevMode.arg("benchDisplays") ?? "1,2").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 }
        let seconds = DevMode.arg("benchSeconds").flatMap(Double.init) ?? 20
        let rounds = DevMode.arg("benchRounds").flatMap(Int.init) ?? 3
        let half = (DevMode.arg("benchHalfSpeed") ?? "off").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) == "on" }
        Task { @MainActor in
            let report = target == "idle" ? await PlaybackBench.idle(seconds: max(2, seconds), rounds: max(1, rounds))
                : await PlaybackBench.run(files: PlaybackBench.videos(at: target), displays: displays.isEmpty ? [1, 2] : displays,
                                          seconds: max(2, seconds), rounds: max(1, rounds), halfSpeed: half.isEmpty ? [false] : half)
            let out = Paths.support.appendingPathComponent("bench.json")
            if let d = try? JSONSerialization.data(withJSONObject: ProcessMeter.jsonSafe(report), options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out) }
            print("BENCH \(out.path)")
            exit(0)
        }
        app.run()
    }

    static func runShots() {
        guard DevMode.shots, let out = DevMode.arg("lucidShots") else {
            FileHandle.standardError.write(Data("lucidShots needs LUCID_SUPPORT_DIR (a throwaway folder).\n".utf8))
            exit(2)
        }
        LucidEngine.setsDesktopPicture = false
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let written = await DevShots.run(to: URL(fileURLWithPath: out, isDirectory: true))
            written.forEach { print("SHOT \($0)") }
            exit(written.isEmpty ? 1 : 0)
        }
        app.run()
    }
}
