// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Background downloads with progress.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// MARK: - Downloader
// A download goes: bytes (with a real percentage) -> size check -> optional conversion to HEVC -> optional seamless
// loop -> decode check -> library. Every in-progress file is a hidden `.partial-*` name in Media/ (so the folder scan
// never adopts a half-made file) and only gets its real name once it passed every check. Conversion steps show their
// own text with a spinner, can be cancelled, and stop after DownloadPolicy.conversionTimeout.

@MainActor final class Downloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    /// What each active download is doing (nil = not downloading). Views show `label` and `fraction`.
    @Published var progress: [String: DownloadPhase] = [:]
    @Published var errors: [String: String] = [:]
    private typealias Job = (item: WallItem, done: (WallItem) -> Void)
    private var session: URLSession!
    private var jobs: [Int: Job] = [:]
    private var tasksByItem: [String: URLSessionDownloadTask] = [:]
    private var work: [String: Task<Void, Never>] = [:]   // conversion and checks after the bytes arrived
    private var failed: [String: Job] = [:]               // what Retry re-runs
    /// Limit for each conversion step (a development run may shorten it to test the timeout).
    var conversionTimeout = DownloadPolicy.conversionTimeout
    /// Development check hook: called on every phase change (not every percent).
    static var phaseHook: ((String, DownloadPhase) -> Void)?
    /// Development check hook: called just before the thumbnail is made (lets the check cancel at that moment).
    static var beforeThumbnailHook: ((String) -> Void)?

    override init() {
        super.init()
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["User-Agent": Net.ua]
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 6 * 3600
        session = URLSession(configuration: c, delegate: self, delegateQueue: .main)
    }

    func start(_ item: WallItem, done: @escaping (WallItem) -> Void) {
        guard progress[item.id] == nil, let s = item.downloadURL, let u = URL(string: s) else { return }
        errors[item.id] = nil
        failed[item.id] = nil
        let t = session.downloadTask(with: u)
        jobs[t.taskIdentifier] = (item, done)
        tasksByItem[item.id] = t
        setPhase(item.id, .downloading(fraction: nil))
        t.resume()
    }
    /// The last failed download of this item can be tried again (same action: download or set as wallpaper).
    func canRetry(_ id: String) -> Bool { failed[id] != nil }
    func retry(_ id: String) {
        guard let j = failed.removeValue(forKey: id) else { return }
        start(j.item, done: j.done)
    }
    /// Stops the download or the conversion after it; the conversion task deletes its temporary files.
    /// The job is forgotten too, so a "finished" callback already on its way can't bring the download back.
    func cancel(_ id: String) {
        if let t = tasksByItem.removeValue(forKey: id) {
            jobs[t.taskIdentifier] = nil
            t.cancel()
        }
        work.removeValue(forKey: id)?.cancel()
        progress[id] = nil
    }

    private func setPhase(_ id: String, _ p: DownloadPhase) {
        let old = progress[id]
        guard old != p else { return }
        progress[id] = p
        if let hook = Self.phaseHook, old?.label.hasPrefix("Downloading") != true || !p.label.hasPrefix("Downloading") { hook(id, p) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let tid = downloadTask.taskIdentifier
        MainActor.assumeIsolated {
            guard let job = jobs[tid] else { return }
            let p = DownloadPhase.downloading(written: totalBytesWritten, expected: totalBytesExpectedToWrite)
            if progress[job.item.id]?.label != p.label { setPhase(job.item.id, p) }   // publish only when the text changes
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tid = downloadTask.taskIdentifier
        let http = downloadTask.response as? HTTPURLResponse
        let status = http?.statusCode ?? 200
        let expected = downloadTask.response?.expectedContentLength ?? -1
        let encoding = http?.value(forHTTPHeaderField: "Content-Encoding")
        MainActor.assumeIsolated {
            // `location` is deleted when this returns, so move it now, under a hidden name with the real extension
            // (AVFoundation and ffmpeg go by it).
            let ext = jobs[tid].map { Self.downloadExt($0.item) } ?? "bin"
            let tmp = Paths.media.appendingPathComponent("\(DownloadPolicy.partialPrefix)\(tid)-\(UUID().uuidString).\(ext)")
            var moveError: String?
            do { try FileManager.default.moveItem(at: location, to: tmp) } catch { moveError = error.localizedDescription }
            finish(tid: tid, tmp: tmp, status: status, expected: expected, encoding: encoding, moveError: moveError)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let tid = task.taskIdentifier
        MainActor.assumeIsolated {
            guard let job = jobs.removeValue(forKey: tid) else { return }
            tasksByItem[job.item.id] = nil
            if (error as NSError).code == NSURLErrorCancelled { progress[job.item.id] = nil }
            else { fail(job, error.localizedDescription) }
        }
    }

    private static func downloadExt(_ item: WallItem) -> String {
        DownloadPolicy.downloadExt(fileExt: item.fileExt, downloadURL: item.downloadURL, kind: item.kind)
    }

    private func fail(_ job: Job, _ message: String, removing files: [URL] = []) {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        let id = job.item.id
        progress[id] = nil
        work[id] = nil
        errors[id] = message
        failed[id] = job
        NSLog("Lucid download failed for \(id): \(message)")
    }

    private func finish(tid: Int, tmp: URL, status: Int, expected: Int64, encoding: String?, moveError: String?) {
        guard let job = jobs.removeValue(forKey: tid) else { try? FileManager.default.removeItem(at: tmp); return }
        tasksByItem[job.item.id] = nil
        if let moveError { fail(job, moveError, removing: [tmp]); return }
        guard (200..<300).contains(status) else { fail(job, "Download failed (HTTP \(status)).", removing: [tmp]); return }
        // URLSession can report success for a body the server cut short: the size must match the announced length.
        let actual = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
        if let m = DownloadPolicy.sizeProblem(expected: expected, actual: actual, contentEncoding: encoding) {
            fail(job, m, removing: [tmp]); return
        }
        let id = job.item.id
        work[id] = Task { @MainActor [weak self] in await self?.process(job, tmp) }
    }

    /// Conversion, loop and decode check, then the file gets its real name and joins the library.
    private func process(_ job: Job, _ downloaded: URL) async {
        let fm = FileManager.default
        var item = job.item
        let id = item.id
        var file = downloaded
        var temps: Set<URL> = [downloaded]
        func cleanup() { temps.forEach { try? fm.removeItem(at: $0) } }
        /// A failure after Cancel is just the cancel: delete the temporary files and say nothing.
        func bail(_ message: String) { cleanup(); if !Task.isCancelled { fail(job, message) } }
        let base = downloaded.deletingPathExtension().path
        var finalExt = downloaded.pathExtension
        let seamless = UserDefaults.standard.object(forKey: "seamlessLoops") as? Bool ?? true
        for step in DownloadPolicy.steps(kind: item.kind, ext: file.pathExtension, source: item.source, seamlessLoops: seamless) {
            if Task.isCancelled { cleanup(); return }
            setPhase(id, step)
            switch step {
            case .converting:
                let src = file, mp4 = URL(fileURLWithPath: base + "-hevc.mp4")
                temps.insert(mp4)
                do {
                    try await withDeadline(conversionTimeout) { try await Transcoder.toHEVC(src, mp4) }
                    // ffmpeg converts a cut-off WebM into a shorter clip and exits 0: compare with the declared length.
                    if let m = DownloadPolicy.durationProblem(declared: await Transcoder.declaredDuration(src),
                                                              converted: await Media.duration(mp4.path)) { bail(m); return }
                } catch { bail(error.localizedDescription); return }
                try? fm.removeItem(at: src); temps.remove(src)
                file = mp4; finalExt = "mp4"; item.fileExt = "mp4"; item.codec = "hevc"
            case .looping:
                let src = file, looped = URL(fileURLWithPath: base + ".loop.mp4")
                temps.insert(looped)
                do {
                    try await withDeadline(conversionTimeout) { try await LoopMaker.make(src, to: looped) }
                    try? fm.removeItem(at: src); temps.remove(src)
                    file = looped; item.codec = "hevc"
                } catch {
                    if Task.isCancelled { cleanup(); return }
                    // A clip that can't be looped is still a fine wallpaper: keep the original.
                    try? fm.removeItem(at: looped); temps.remove(looped)
                    NSLog("LoopMaker failed for \(id): \(error.localizedDescription) — using original")
                }
            case .checking:
                if let m = await Media.verify(file, item.kind) { bail(m); return }
            case .downloading:
                break
            }
        }
        if Task.isCancelled { cleanup(); return }
        // Size, dimensions and thumbnail come from the still-hidden file; the real name appears only in the same
        // step that adds the item to the library (no wait in between), and a Cancel up to then leaves nothing.
        let hadThumb = fm.fileExists(atPath: Media.thumbURL(id: id).path)
        if let (w, h) = await Media.dims(file.path, item.kind) { item.width = w; item.height = h }
        item.bytes = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? item.bytes
        Self.beforeThumbnailHook?(id)
        let thumb = await Media.thumbnail(file.path, item.kind, id: id)
        func dropThumb() { if !hadThumb, let thumb { try? fm.removeItem(atPath: thumb) } }
        if Task.isCancelled { dropThumb(); cleanup(); return }
        let final = Paths.media.appendingPathComponent("\(Paths.safe(id)).\(finalExt)")
        try? fm.removeItem(at: final)
        do { try fm.moveItem(at: file, to: final) } catch { dropThumb(); bail(error.localizedDescription); return }
        temps.remove(file); cleanup()
        item.localPath = final.path
        item.thumbPath = thumb
        item.addedAt = Date()
        progress[id] = nil
        work[id] = nil
        job.done(item)
    }

    /// At launch: delete what an interrupted download left in Media/ (only regular `.partial-*` and old `live_*.loop.mp4`
    /// files, never one the library uses). Returns the names removed.
    @discardableResult static func cleanLeftovers(keep: Set<String>, in dir: URL = Paths.media) -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        // attributesOfItem does not follow symlinks, so a link named like a leftover is never treated as a file.
        let entries = names.map { n in
            (name: n, isRegularFile: (try? fm.attributesOfItem(atPath: dir.appendingPathComponent(n).path)[.type] as? FileAttributeType) == .typeRegular)
        }
        let gone = DownloadPolicy.leftovers(entries, keep: keep)
        for n in gone { try? fm.removeItem(at: dir.appendingPathComponent(n)) }
        if !gone.isEmpty { NSLog("Lucid removed \(gone.count) unfinished download file(s) from Media/") }
        return gone
    }
}
