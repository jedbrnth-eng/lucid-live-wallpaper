// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Running a command-line tool (ffmpeg, ffprobe) from async code, stoppable by task cancellation.
// Foundation only, so it is unit-tested with real child processes.
import Foundation

enum ProcessRunner {
    /// Runs a tool to completion; cancelling the task stops it (SIGTERM, then SIGKILL if it is still running
    /// `killAfter` seconds later, e.g. an ffmpeg wedged in the hardware encoder). Standard output is read while the
    /// tool runs, so a chatty tool can't block on a full pipe; `captureOutput: false` discards it.
    static func run(_ tool: String, _ args: [String], captureOutput: Bool = true,
                    killAfter: TimeInterval = 2) async throws -> (status: Int32, output: String) {
        let box = ProcessBox(killAfter: killAfter)
        let p = box.process
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = captureOutput ? Pipe() : nil
        p.standardOutput = pipe ?? FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let reader = OutputReader()
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Int32, Error>) in
                p.terminationHandler = { c.resume(returning: $0.terminationStatus) }
                box.lock.lock(); defer { box.lock.unlock() }
                if box.cancelled { p.terminationHandler = nil; c.resume(throwing: CancellationError()); return }
                do { try p.run() } catch { p.terminationHandler = nil; c.resume(throwing: error); return }
                if let pipe { reader.start(pipe.fileHandleForReading) }
            }
        } onCancel: { box.cancel() }
        let out = await reader.result()
        return (status, String(data: out, encoding: .utf8) ?? "")
    }
}

/// Reads a pipe to its end on a background thread while the tool runs.
private final class OutputReader: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let group = DispatchGroup()
    func start(_ h: FileHandle) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let d = (try? h.readToEnd()) ?? Data()
            self.lock.withLock { self.data = d }
            self.group.leave()
        }
    }
    func result() async -> Data {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in group.notify(queue: .global()) { c.resume() } }
        return lock.withLock { data }
    }
}

/// A child process that a cancelled task can stop from any thread.
final class ProcessBox: @unchecked Sendable {
    let process = Process()
    let lock = NSLock()
    private let killAfter: TimeInterval
    private(set) var cancelled = false
    init(killAfter: TimeInterval = 2) { self.killAfter = killAfter }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + killAfter) { [weak self] in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            // Still our child (not reaped yet, so the pid can't have been reused): force it.
            if self.process.isRunning && self.process.processIdentifier == pid { kill(pid, SIGKILL) }
        }
    }
}
