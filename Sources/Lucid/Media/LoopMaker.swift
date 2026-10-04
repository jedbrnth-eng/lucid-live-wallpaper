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
    static func toHEVC(_ src: URL, _ dst: URL) async throws {
        guard let ff = ffmpeg else { throw NSError(domain: "tx", code: 1, userInfo: [NSLocalizedDescriptionKey: "Needs ffmpeg (brew install ffmpeg) to convert WebM"]) }
        try? FileManager.default.removeItem(at: dst)
        let code: Int32 = try await withCheckedThrowingContinuation { c in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ff)
            p.arguments = ["-v", "error", "-y", "-i", src.path, "-map", "0:v:0", "-an",
                           "-vf", "scale='min(3840,iw)':-2:flags=lanczos,format=yuv420p",
                           "-c:v", "hevc_videotoolbox", "-q:v", "65", "-tag:v", "hvc1", "-movflags", "+faststart", dst.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { c.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { c.resume(throwing: error) }
        }
        guard code == 0, FileManager.default.fileExists(atPath: dst.path) else {
            throw NSError(domain: "tx", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "ffmpeg conversion failed (\(code))"]) }
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
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in box.session.exportAsynchronously { c.resume() } }
        if ex.status != .completed {
            throw ex.error ?? NSError(domain: "loop", code: 5, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
    }
}
