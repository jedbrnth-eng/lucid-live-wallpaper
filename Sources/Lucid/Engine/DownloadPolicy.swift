// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// What a download shows while it works, and the checks it must pass before a file joins the library,
// as pure logic (no network, files or AVFoundation), so it is fully unit-tested.
// Downloader feeds in what it sees: bytes written, the server's Content-Length, durations, file names.
import Foundation

/// The step a download is on. Shown as text, never as a frozen "99%".
enum DownloadPhase: Equatable {
    /// Receiving bytes. `fraction` is 0...1 when the server sent a size, nil when it didn't.
    case downloading(fraction: Double?)
    /// Re-encoding WebM/OGV/MKV to HEVC so macOS can play it (ffmpeg).
    case converting
    /// Building the cross-faded seamless loop.
    case looping
    /// Making sure the file is complete and opens.
    case checking

    static func downloading(written: Int64, expected: Int64) -> DownloadPhase {
        guard expected > 0 else { return .downloading(fraction: nil) }
        return .downloading(fraction: min(max(Double(written) / Double(expected), 0), 1))
    }

    /// Progress bar value; nil means show an indeterminate spinner (the step's length can't be known).
    var fraction: Double? {
        if case .downloading(let f) = self { return f }
        return nil
    }

    var label: String {
        switch self {
        case .downloading(let f?): return "Downloading \(Int((f * 100).rounded(.down)))%"
        case .downloading(nil): return "Downloading…"
        case .converting: return "Converting for Mac…"
        case .looping: return "Making a seamless loop…"
        case .checking: return "Checking the file…"
        }
    }
}

enum DownloadPolicy {
    /// A conversion step (ffmpeg or the loop export) that takes longer than this is stopped and reported.
    /// Generous: a long 4K clip on an older Mac can take several minutes.
    static let conversionTimeout: TimeInterval = 15 * 60

    /// Hidden name prefix for every in-progress file in Media/ (download, conversion, loop). Hidden files are
    /// never adopted by the "files dropped into the Lucid folder" scan, and leftovers are removed at launch.
    static let partialPrefix = ".partial-"

    /// Extensions Lucid converts to HEVC with ffmpeg because AVFoundation can't play them.
    static let transcodeExts: Set<String> = ["webm", "ogv", "mkv"]

    /// Steps after the bytes arrive, in order.
    static func steps(kind: Kind, ext: String, source: Source, seamlessLoops: Bool) -> [DownloadPhase] {
        guard kind == .video else { return [.checking] }
        var s: [DownloadPhase] = []
        if transcodeExts.contains(ext.lowercased()) { s.append(.converting) }
        if source == .live && seamlessLoops { s.append(.looping) }
        s.append(.checking)
        return s
    }

    /// nil when the received file has the size the server announced; otherwise the message to show.
    /// `expected` <= 0 means the server sent no length (nothing to compare). With a compressed transfer
    /// encoding the announced length is the compressed size, so it can't be compared either.
    static func sizeProblem(expected: Int64, actual: Int64, contentEncoding: String? = nil) -> String? {
        if actual <= 0 { return "The download was empty." }
        let enc = contentEncoding?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        guard expected > 0, enc.isEmpty || enc == "identity" else { return nil }
        if actual < expected { return "The download was cut off (\(mb(actual)) of \(mb(expected)))." }
        if actual > expected { return "The download doesn't match its announced size (\(mb(actual)), expected \(mb(expected)))." }
        return nil
    }

    /// nil when a converted clip is about as long as its source said it was. ffmpeg happily converts a cut-off
    /// WebM into a shorter video and exits 0, so this catches truncation even when the server sent no length.
    static func durationProblem(declared: Double?, converted: Double?) -> String? {
        guard let converted, converted.isFinite, converted > 0 else { return "The converted video has no frames." }
        guard let declared, declared.isFinite, declared > 0 else { return nil }
        if converted < declared * 0.9 - 0.5 {
            return "The video is incomplete (\(Int(converted.rounded())) s of \(Int(declared.rounded())) s); the download was probably cut off."
        }
        return nil
    }

    /// nil unless a photo's own bytes show it was cut off: a JPEG must end with its end-of-image marker, a PNG with
    /// its IEND chunk, a WebP's RIFF size must match the file. ImageIO decodes a cut-off JPEG without complaint
    /// (the missing part comes out grey), so this is checked separately. Other formats: nil (not checked here).
    /// `head` = the first bytes, `tail` = the last bytes (a few KB), `size` = the file size.
    static func imageEndProblem(head: [UInt8], tail: [UInt8], size: Int64) -> String? {
        let cut = "The downloaded photo is incomplete; the download was probably cut off."
        func has(_ needle: [UInt8], in hay: [UInt8]) -> Bool {
            guard needle.count <= hay.count else { return false }
            return (0...(hay.count - needle.count)).contains { i in hay[i..<(i + needle.count)].elementsEqual(needle) }
        }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return has([0xFF, 0xD9], in: tail) ? nil : cut }   // JPEG EOI
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return has(Array("IEND".utf8), in: tail) ? nil : cut }
        if head.count >= 12, head.starts(with: Array("RIFF".utf8)), Array(head[8..<12]) == Array("WEBP".utf8) {
            let declared = Int64(head[4]) | Int64(head[5]) << 8 | Int64(head[6]) << 16 | Int64(head[7]) << 24
            return declared + 8 <= size ? nil : cut
        }
        return nil
    }

    /// Names in Media/ that are leftovers of an interrupted download or loop and may be deleted at launch:
    /// only regular files named `.partial-*` or `*.loop.mp4`, and never a file the library points to.
    static func leftovers(_ entries: [(name: String, isRegularFile: Bool)], keep: Set<String> = []) -> [String] {
        entries.filter { e in
            e.isRegularFile && !keep.contains(e.name) && !e.name.contains("/")
                && (e.name.hasPrefix(partialPrefix) || e.name.lowercased().hasSuffix(".loop.mp4"))
        }.map(\.name)
    }

    private static func mb(_ b: Int64) -> String { String(format: "%.1f MB", Double(b) / 1_000_000) }
}

struct DownloadTimeout: Error, LocalizedError {
    let seconds: TimeInterval
    var errorDescription: String? {
        let limit = seconds >= 120 ? "\(Int(seconds / 60)) minutes" : "\(Int(seconds)) seconds"
        return "Converting took longer than \(limit) and was stopped."
    }
}

/// Runs `op`, cancelling it and throwing `DownloadTimeout` if it hasn't finished within `seconds`.
/// `op` must react to cancellation (Transcoder terminates ffmpeg, LoopMaker cancels its export).
func withDeadline<T: Sendable>(_ seconds: TimeInterval, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { g in
        g.addTask { try await op() }
        g.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
            throw DownloadTimeout(seconds: seconds)
        }
        defer { g.cancelAll() }
        guard let first = try await g.next() else { throw CancellationError() }
        return first
    }
}
