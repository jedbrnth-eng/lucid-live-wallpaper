// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// The headless playback benchmark (started by Headless.swift, never draws). For each video and each display
// count N it builds N wallpaper surfaces exactly as the desktop does (ScreenSurface: looping player and
// AVPlayerLayer per display) in windows that are never shown, lets them play, and measures this process with
// ProcessMeter: CPU %, the kernel's CPU energy estimate, memory footprint and wakeups. Rounds are interleaved
// and each figure is the median of the rounds.
// Not included: the window server compositing each frame, the display itself and the media engine's own power,
// so a wallpaper on screen costs more in total. Other work on the Mac skews the figures, so every run records the
// 1-minute load average; compare builds at similar load, or by ratios within one run (for example 2 displays vs 1).
import AppKit
import AVFoundation

@MainActor enum PlaybackBench {
    static let warmUp = 4.0

    /// A single video, or every video directly inside a folder (sorted by name).
    static func videos(at path: String) -> [String] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else { return [path] }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted()
            .filter { !$0.hasPrefix(".") && ImportPolicy.kind(forExtension: URL(fileURLWithPath: $0).pathExtension) == .video }
            .map { dir.appendingPathComponent($0).path }
    }

    static func run(files: [String], displays: [Int], seconds: Double, rounds: Int) async -> [String: Any] {
        guard let screen = NSScreen.screens.first else { return ["error": "no screen"] }
        guard !files.isEmpty else { return ["error": "no video found"] }
        var measured: [String: [ProcessRates]] = [:]
        var loads: [String: [Double]] = [:]
        var shape: [String: [String: Any]] = [:]
        for _ in 0..<rounds {
            for f in files {
                for n in displays {
                    let a = Assignment(itemID: "bench", title: "Bench", path: f, kind: .video)
                    let surfaces = (0..<n).map { ScreenSurface(screen: screen, key: "bench-\($0)", assignment: a) }
                    surfaces.forEach { $0.setRunning(true) }
                    await wait(warmUp)
                    let s0 = ProcessMeter.sample(), l0 = ProcessMeter.load1()
                    await wait(seconds)
                    let s1 = ProcessMeter.sample(), l1 = ProcessMeter.load1()
                    measured["\(f)|\(n)", default: []].append(ProcessMeter.rates(from: s0, to: s1))
                    loads["\(f)|\(n)", default: []].append(((l0 + l1) / 2 * 10).rounded() / 10)
                    let times = surfaces.compactMap { $0.player?.currentTime().seconds }
                    shape["\(f)|\(n)"] = [
                        "players": Set(surfaces.compactMap { $0.player.map(ObjectIdentifier.init) }).count,
                        "layers_ready": surfaces.filter { ($0.host?.contentLayer as? AVPlayerLayer)?.isReadyForDisplay == true }.count,
                        "surfaces_running": surfaces.filter(\.isRunning).count,
                        "playhead_spread_ms": ProcessMeter.spreadMilliseconds(times),
                    ]
                    surfaces.forEach { $0.close() }
                    await wait(1.5)
                }
            }
        }
        var results: [[String: Any]] = []
        for f in files {
            let info = await describe(f)
            for n in displays {
                let rs = measured["\(f)|\(n)"] ?? []
                var row = info
                row["displays"] = n
                row["cpu_pct"] = ProcessMeter.median(rs.map(\.cpuPercent))
                row["cpu_energy_mw"] = ProcessMeter.median(rs.map(\.energyMilliwatts))
                row["footprint_mb"] = ProcessMeter.median(rs.map(\.footprintMB))
                row["wakeups_per_s"] = ProcessMeter.median(rs.map(\.wakeupsPerSecond))
                row["cpu_pct_rounds"] = rs.map(\.cpuPercent)
                row["load1_rounds"] = loads["\(f)|\(n)"] ?? []
                row["load1"] = ProcessMeter.median(loads["\(f)|\(n)"] ?? [])
                for (k, v) in shape["\(f)|\(n)"] ?? [:] { row[k] = v }
                results.append(row)
            }
        }
        return ["seconds_per_run": seconds, "warm_up_seconds": warmUp, "rounds": rounds, "cpu": ProcessMeter.cpuBrand,
                "cores": ProcessInfo.processInfo.activeProcessorCount,
                "os": ProcessInfo.processInfo.operatingSystemVersionString, "results": results,
                "scope": "this process only: decode and playback; not the window server, the display or media-engine power"]
    }

    /// Codec, size, frame rate and length, for the report.
    private static func describe(_ path: String) async -> [String: Any] {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        var d: [String: Any] = ["file": URL(fileURLWithPath: path).lastPathComponent]
        if let t = try? await asset.loadTracks(withMediaType: .video).first,
           let (size, fps, formats) = try? await t.load(.naturalSize, .nominalFrameRate, .formatDescriptions) {
            d["size"] = "\(Int(size.width))x\(Int(size.height))"
            d["fps"] = Int(fps.rounded())
            if let f = formats.first {
                let c = CMFormatDescriptionGetMediaSubType(f)
                d["codec"] = String(bytes: [24, 16, 8, 0].map { UInt8((c >> $0) & 0xFF) }, encoding: .ascii) ?? "?"
            }
        }
        if let dur = try? await asset.load(.duration), let s = ProcessMeter.seconds(dur.seconds) { d["length_s"] = s }
        return d
    }

    private static func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
}
