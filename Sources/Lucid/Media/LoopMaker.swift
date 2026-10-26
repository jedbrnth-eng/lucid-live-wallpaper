// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Transcoding and seamless cross-faded loop creation.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// MARK: - Seamless loop maker
// Most source clips are not authored as loops: the last frame jumps back to the first.
// We build a new file where the tail cross-fades into the head, so playback wraps invisibly.
// Audio is dropped (wallpapers are muted anyway, and soundtrack licences often differ from the footage).

final class ExportBox: @unchecked Sendable { let session: AVAssetExportSession; init(_ s: AVAssetExportSession) { session = s } }

enum Transcoder {
    static let ffmpeg: String? = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// WebM/VP9/AV1 -> HEVC MP4 (hardware encoder, no audio) so AVFoundation can play it.
    /// Cancelling the calling task stops ffmpeg (SIGTERM) and throws CancellationError.
    static func toHEVC(_ src: URL, _ dst: URL) async throws {
        guard let ff = ffmpeg else { throw NSError(domain: "tx", code: 1, userInfo: [NSLocalizedDescriptionKey: "Needs ffmpeg (brew install ffmpeg) to convert WebM"]) }
        try? FileManager.default.removeItem(at: dst)
        let code = try await run(ff, ["-v", "error", "-y", "-i", src.path, "-map", "0:v:0", "-an",
                                      "-vf", "scale='min(3840,iw)':-2:flags=lanczos,format=yuv420p",
                                      "-c:v", "hevc_videotoolbox", "-q:v", "65", "-tag:v", "hvc1", "-movflags", "+faststart", dst.path]).status
        if Task.isCancelled { try? FileManager.default.removeItem(at: dst); throw CancellationError() }
        guard code == 0, FileManager.default.fileExists(atPath: dst.path) else {
            throw NSError(domain: "tx", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "ffmpeg conversion failed (\(code))"]) }
    }

    /// The length the source file's container declares (ffprobe), or nil. A cut-off WebM still declares its full
    /// length while ffmpeg converts only what arrived, so comparing the two catches a truncated download.
    static func declaredDuration(_ src: URL) async -> Double? {
        guard let ff = ffmpeg else { return nil }
        let probe = URL(fileURLWithPath: ff).deletingLastPathComponent().appendingPathComponent("ffprobe").path
        guard FileManager.default.isExecutableFile(atPath: probe),
              let r = try? await run(probe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", src.path]),
              r.status == 0 else { return nil }
        return Double(r.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Runs a tool to completion; cancelling the task terminates it.
    private static func run(_ tool: String, _ args: [String]) async throws -> (status: Int32, output: String) {
        let box = ProcessBox()
        let p = box.process
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Int32, Error>) in
                p.terminationHandler = { c.resume(returning: $0.terminationStatus) }
                box.lock.lock(); defer { box.lock.unlock() }
                if box.cancelled { p.terminationHandler = nil; c.resume(throwing: CancellationError()); return }
                do { try p.run() } catch { p.terminationHandler = nil; c.resume(throwing: error) }
            }
        } onCancel: { box.cancel() }
        let out = String(data: (try? pipe.fileHandleForReading.readToEnd()) ?? Data(), encoding: .utf8) ?? ""
        return (status, out)
    }
}

/// A child process that a cancelled task can stop from any thread.
final class ProcessBox: @unchecked Sendable {
    let process = Process()
    let lock = NSLock()
    private(set) var cancelled = false
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if process.isRunning { process.terminate() }
    }
}

enum LoopMaker {
    static let fade = 1.5

    static func make(_ src: URL, to dst: URL) async throws {
        let asset = AVURLAsset(url: src)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw NSError(domain: "loop", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track"]) }
        let dur = try await asset.load(.duration)
        let (size, tf, fps) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let D = dur.seconds, F = min(fade, D / 4)
        guard D > 4 else { throw NSError(domain: "loop", code: 2, userInfo: [NSLocalizedDescriptionKey: "Clip too short"]) }
        let ts: CMTimeScale = max(dur.timescale, 600)
        func t(_ x: Double) -> CMTime { CMTime(seconds: x, preferredTimescale: ts) }

        let comp = AVMutableComposition()
        guard let a = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let b = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "loop", code: 3, userInfo: [NSLocalizedDescriptionKey: "Composition failed"]) }
        // A: body [F, D) placed at 0. B: head [0, F) placed at D-2F, underneath A while A fades out.
        try a.insertTimeRange(CMTimeRange(start: t(F), end: dur), of: track, at: .zero)
        try b.insertTimeRange(CMTimeRange(start: .zero, end: t(F)), of: track, at: t(D - 2 * F))
        a.preferredTransform = tf; b.preferredTransform = tf
        let total = t(D - F)

        let ia = AVMutableVideoCompositionLayerInstruction(assetTrack: a)
        ia.setTransform(tf, at: .zero)
        ia.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: CMTimeRange(start: t(D - 2 * F), duration: t(F)))
        let ib = AVMutableVideoCompositionLayerInstruction(assetTrack: b)
        ib.setTransform(tf, at: .zero)
        let ins = AVMutableVideoCompositionInstruction()
        _ = total
        ins.timeRange = CMTimeRange(start: .zero, duration: comp.duration)
        ins.layerInstructions = [ia, ib]
        let vc = AVMutableVideoComposition()
        vc.instructions = [ins]
        let r = CGRect(origin: .zero, size: size).applying(tf)
        vc.renderSize = CGSize(width: abs(r.width), height: abs(r.height))
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(24, min(60, fps.rounded()))))

        let preset = vc.renderSize.width > 3840 ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHEVC3840x2160
        guard let ex = AVAssetExportSession(asset: comp, presetName: preset) else {
            throw NSError(domain: "loop", code: 4, userInfo: [NSLocalizedDescriptionKey: "HEVC export unavailable"]) }
        ex.videoComposition = vc
        ex.shouldOptimizeForNetworkUse = true
        try? FileManager.default.removeItem(at: dst)
        ex.outputURL = dst
        ex.outputFileType = .mp4
        let box = ExportBox(ex)
        // Cancelling the calling task (Cancel button or the 15-minute limit) stops the export.
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in box.session.exportAsynchronously { c.resume() } }
        } onCancel: { box.session.cancelExport() }
        if Task.isCancelled { try? FileManager.default.removeItem(at: dst); throw CancellationError() }
        if ex.status != .completed {
            throw ex.error ?? NSError(domain: "loop", code: 5, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
    }
}
