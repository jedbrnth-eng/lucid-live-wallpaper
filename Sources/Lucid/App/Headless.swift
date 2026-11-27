// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Development runs that must never draw anything: no main window, no menu-bar item, no Dock icon, no desktop
// window and no desktop picture. The SwiftUI app is never started (see LucidMain), the process can't take focus
// (activation policy .prohibited), and wallpaper windows are built but never ordered front. Safe to run while
// your everyday copy of Lucid plays. Used by the playback benchmark:
//   LUCID_SUPPORT_DIR=/tmp/lucid-bench build/Lucid.app/Contents/MacOS/Lucid -lucidBench <video or folder>
//       [-benchDisplays 1,2,3] [-benchSeconds 20] [-benchRounds 3]
// It writes bench.json in LUCID_SUPPORT_DIR and quits. See PlaybackBench.swift for what is measured.
import AppKit

@MainActor enum Headless {
    /// True for the whole headless run: ScreenSurface never orders its window front.
    private(set) static var active = false

    static func runBench() {
        guard DevMode.bench, let target = DevMode.arg("lucidBench") else {
            FileHandle.standardError.write(Data("lucidBench needs LUCID_SUPPORT_DIR (a throwaway folder).\n".utf8))
            exit(2)
        }
        active = true
        LucidEngine.setsDesktopPicture = false
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let displays = (DevMode.arg("benchDisplays") ?? "1,2").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 }
        let seconds = DevMode.arg("benchSeconds").flatMap(Double.init) ?? 20
        let rounds = DevMode.arg("benchRounds").flatMap(Int.init) ?? 3
        Task { @MainActor in
            let report = await PlaybackBench.run(files: PlaybackBench.videos(at: target), displays: displays.isEmpty ? [1, 2] : displays,
                                                 seconds: max(2, seconds), rounds: max(1, rounds))
            let out = Paths.support.appendingPathComponent("bench.json")
            if let d = try? JSONSerialization.data(withJSONObject: ProcessMeter.jsonSafe(report), options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out) }
            print("BENCH \(out.path)")
            exit(0)
        }
        app.run()
    }
}
