// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// The real shared players (AVFoundation, no window or screen needed) with a small generated video.
import Foundation
import AVFoundation
import CoreVideo

/// A 6 s, 320x180, 30 fps clip written once per test run into a temporary folder. Motion JPEG: a software codec,
/// so it also works on CI machines without a hardware video encoder.
enum TestVideo {
    static let path: String? = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("lucid-test-\(getpid()).mov")
        try? FileManager.default.removeItem(at: u)
        // Shared by every test that needs a video; removed when the test run exits.
        atexit { try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("lucid-test-\(getpid()).mov")) }
        guard let w = try? AVAssetWriter(outputURL: u, fileType: .mov) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.jpeg, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let px = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        w.add(input)
        guard w.startWriting() else { return nil }
        w.startSession(atSourceTime: .zero)
        for i in 0..<180 {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA, nil, &pb)
            guard let pb else { return nil }
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) { memset(base, Int32(i % 255), CVPixelBufferGetDataSize(pb)) }
            CVPixelBufferUnlockBaseAddress(pb, [])
            px.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        w.finishWriting { done.signal() }
        done.wait()
        return w.status == .completed ? u.path : nil
    }()
}

func registerSharedPlayerTests() {
    /// Runs the main run loop until `done` or `limit` seconds.
    func spin(_ limit: Double, until done: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(limit)
        while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    test("Shared players: a new-speed player starts where the old one is, not from 0 (speed change)") {
        guard let v = TestVideo.path else { expect(false, "could not write the test video"); return }
        MainActor.assumeIsolated {
            let sp = SharedPlayers()
            let p = sp.acquire(path: v, speed: 0.5, holder: "new")
            var oldPlayhead = 1.0
            sp.seek(path: v, speed: 0.5) { CMTime(seconds: oldPlayhead, preferredTimescale: 600) }
            oldPlayhead = 2.5   // the old player moved on before the new one had its video: read the time when seeking
            sp.setRunning(true, path: v, speed: 0.5, holder: "new")
            spin(5) { p.currentItem?.status == .readyToPlay && p.currentTime().seconds > 0.05 }
            spin(0.4)
            let t = p.currentTime().seconds
            expect(t >= 2.4 && t < 4, "playhead at \(t) s; expected about 2.7 s (2.5 s when the seek ran, then 0.5x)")
            sp.release(path: v, speed: 0.5, holder: "new")
            expectEqual(sp.count, 0)
        }
    }
    test("Shared players: a seek still waiting when the last window closes is dropped safely") {
        guard let v = TestVideo.path, FileManager.default.fileExists(atPath: v) else { expect(false, "no test video"); return }
        MainActor.assumeIsolated {
            let sp = SharedPlayers()
            _ = sp.acquire(path: v, speed: 1, holder: "a")
            var asked = 0
            sp.seek(path: v, speed: 1) { asked += 1; return CMTime(seconds: 1, preferredTimescale: 600) }
            sp.release(path: v, speed: 1, holder: "a")
            spin(0.5)
            expectEqual(sp.count, 0)
            expectEqual(asked, 0, "no seek on a released player")
        }
    }
}
