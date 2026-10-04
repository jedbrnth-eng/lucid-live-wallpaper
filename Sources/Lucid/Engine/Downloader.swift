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

@MainActor final class Downloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: [String: Double] = [:]
    @Published var errors: [String: String] = [:]
    private var session: URLSession!
    private var jobs: [Int: (item: WallItem, done: (WallItem) -> Void)] = [:]
    private var tasksByItem: [String: URLSessionDownloadTask] = [:]

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
        let t = session.downloadTask(with: u)
        jobs[t.taskIdentifier] = (item, done)
        tasksByItem[item.id] = t
        progress[item.id] = 0
        t.resume()
    }
    func cancel(_ id: String) {
        tasksByItem[id]?.cancel()
        tasksByItem[id] = nil
        progress[id] = nil
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let tid = downloadTask.taskIdentifier
        MainActor.assumeIsolated {
            guard let job = jobs[tid] else { return }
            progress[job.item.id] = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.01
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tid = downloadTask.taskIdentifier
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        let tmp = Paths.media.appendingPathComponent(".partial-\(tid)-\(UUID().uuidString)")
        try? FileManager.default.moveItem(at: location, to: tmp)
        MainActor.assumeIsolated { finish(tid: tid, tmp: tmp, status: status) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let tid = task.taskIdentifier
        MainActor.assumeIsolated {
            guard let job = jobs.removeValue(forKey: tid) else { return }
            progress[job.item.id] = nil
            tasksByItem[job.item.id] = nil
            if (error as NSError).code != NSURLErrorCancelled { errors[job.item.id] = error.localizedDescription }
        }
    }

    private func finish(tid: Int, tmp: URL, status: Int) {
        guard let job = jobs.removeValue(forKey: tid) else { try? FileManager.default.removeItem(at: tmp); return }
        tasksByItem[job.item.id] = nil
        guard (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: tmp)
            progress[job.item.id] = nil
            errors[job.item.id] = "Download failed (HTTP \(status))."
            return
        }
        var item = job.item
        let ext = item.fileExt ?? URL(string: item.downloadURL ?? "")?.pathExtension ?? (item.kind == .video ? "mp4" : "jpg")
        let final = Paths.media.appendingPathComponent("\(Paths.safe(item.id)).\(ext.isEmpty ? "bin" : ext)")
        try? FileManager.default.removeItem(at: final)
        do { try FileManager.default.moveItem(at: tmp, to: final) } catch {
            progress[item.id] = nil; errors[item.id] = error.localizedDescription; return
        }
        Task { @MainActor in
            var final = final
            if item.kind == .video, ["webm", "ogv", "mkv"].contains(final.pathExtension.lowercased()) {
                self.progress[item.id] = 0.998
                let mp4 = final.deletingPathExtension().appendingPathExtension("mp4")
                do {
                    try await Transcoder.toHEVC(final, mp4)
                    try? FileManager.default.removeItem(at: final)
                    final = mp4; item.fileExt = "mp4"; item.codec = "hevc"
                } catch {
                    try? FileManager.default.removeItem(at: final)
                    try? FileManager.default.removeItem(at: mp4)
                    self.progress[item.id] = nil
                    self.errors[item.id] = error.localizedDescription
                    return
                }
            }
            if item.kind == .video && item.source == .live && UserDefaults.standard.object(forKey: "seamlessLoops") as? Bool ?? true {
                self.progress[item.id] = 0.999
                let looped = Paths.media.appendingPathComponent("\(Paths.safe(item.id)).loop.mp4")
                do {
                    try await LoopMaker.make(final, to: looped)
                    try? FileManager.default.removeItem(at: final)
                    try FileManager.default.moveItem(at: looped, to: final)
                    item.codec = "hevc"
                } catch {
                    try? FileManager.default.removeItem(at: looped)
                    NSLog("LoopMaker failed for \(item.id): \(error.localizedDescription) — using original")
                }
            }
            if let (w, h) = await Media.dims(final.path, item.kind) { item.width = w; item.height = h }
            item.localPath = final.path
            item.bytes = (try? FileManager.default.attributesOfItem(atPath: final.path)[.size] as? Int64) ?? item.bytes
            item.thumbPath = await Media.thumbnail(final.path, item.kind, id: item.id)
            item.addedAt = Date()
            self.progress[item.id] = nil
            job.done(item)
        }
    }
}
