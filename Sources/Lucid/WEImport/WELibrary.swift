// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Wallpaper Engine sync: watches the folders the user picked (plus Steam's Mac folders if they ever appear),
// rescans on launch and on change, and keeps the "Wallpaper Engine" library page in step.
// Items are local references only: nothing is copied except WebM->HEVC conversions cached for playback.
import Foundation
import CoreServices
import SwiftUI

@MainActor final class WELibrary: ObservableObject {
    @Published private(set) var items: [WallItem] = []
    @Published private(set) var folders: [String] = Pref.weFolders
    @Published private(set) var autoFolders: [String] = []
    @Published private(set) var counts = WECounts()
    @Published private(set) var errors: [String] = []
    @Published private(set) var scanning = false
    @Published private(set) var lastScan: Date?
    @Published var converting: Set<String> = []
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var steamTimer: Timer?
    private var scanGeneration = 0
    var onRemoved: ((_ paths: [String]) -> Void)?
    var flash: ((String) -> Void)?

    init() {
        if let d = try? Data(contentsOf: Paths.weIndex), let l = try? JSONDecoder().decode([WallItem].self, from: d) { items = l; recount() }
        // Steam for Mac never ships Wallpaper Engine content, but re-check now and then in case a library appears.
        steamTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSteamFolders() }
        }
    }

    var roots: [URL] { (folders + autoFolders).map { URL(fileURLWithPath: $0, isDirectory: true) } }

    func start() { checkSteamFolders(force: true) }

    private func checkSteamFolders(force: Bool = false) {
        let found = WEScanner.detectSteamFolders(home: FileManager.default.homeDirectoryForCurrentUser).map(\.path)
        if found != autoFolders || force { autoFolders = found; restartWatcher(); rescan() }
    }

    func addFolder(_ url: URL) {
        let p = url.standardizedFileURL.path
        guard !folders.contains(p) else { rescan(); return }
        folders.append(p); Pref.weFolders = folders
        restartWatcher(); rescan(announce: true)
    }
    func removeFolder(_ path: String) {
        folders.removeAll { $0 == path }; Pref.weFolders = folders
        restartWatcher(); rescan()
    }

    private func recount() {
        var c = WECounts()
        for i in items { switch i.weSupport { case .video?: c.video += 1; case .web?: c.web += 1; default: c.unsupported += 1 } }
        counts = c
    }

    func rescan(announce: Bool = false) {
        scanGeneration += 1
        let gen = scanGeneration, roots = self.roots
        scanning = true
        Task {
            let r = await Task.detached(priority: .utility) { WEScanner.scan(roots: roots) }.value
            guard gen == self.scanGeneration else { return }
            let old = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            var next: [WallItem] = []
            for e in r.entries { next.append(await self.wallItem(e, previous: old[e.id])) }
            guard gen == self.scanGeneration else { return }
            let removedIDs = Set(old.keys).subtracting(next.map(\.id))
            let removedPaths = removedIDs.compactMap { old[$0] }.flatMap { [$0.weMainFile, $0.localPath].compactMap { $0 } }
            items = next
            errors = r.errors
            lastScan = Date()
            scanning = false
            recount()
            if let d = try? JSONEncoder().encode(items) { try? d.write(to: Paths.weIndex, options: .atomic) }
            if !removedPaths.isEmpty { onRemoved?(removedPaths) }
            if announce || !removedIDs.isEmpty {
                flash?("Wallpaper Engine: \(counts.video) video · \(counts.web) web · \(counts.unsupported) not playable on Mac"
                       + (removedIDs.isEmpty ? "" : " · \(removedIDs.count) removed"))
            }
        }
    }

    static func cachePath(_ id: String) -> URL { Paths.weCache.appendingPathComponent(Paths.safe(id) + ".mp4") }

    private func wallItem(_ e: WEEntry, previous: WallItem?) async -> WallItem {
        let ready: String? = {
            guard e.support != .unsupported, let f = e.mainFile else { return nil }
            if e.needsConversion { let c = Self.cachePath(e.id).path; return FileManager.default.fileExists(atPath: c) ? c : nil }
            return f
        }()
        let kind: Kind = e.support == .web ? .web : .video
        var it = WallItem(id: e.id, source: .wallpaperEngine, kind: kind, title: e.title,
                          width: previous?.width ?? 0, height: previous?.height ?? 0,
                          pageURL: e.workshopID.map { "https://steamcommunity.com/sharedfiles/filedetails/?id=\($0)" },
                          author: "Wallpaper Engine · \(e.type.label)",
                          license: "Your own Wallpaper Engine item, linked from your folder. Rights stay with its creator; Lucid never copies or shares it.",
                          category: e.type.label, localPath: ready)
        it.tags = e.tags.isEmpty ? nil : e.tags
        it.addedAt = previous?.addedAt ?? Date()
        it.lastAppliedAt = previous?.lastAppliedAt
        it.weSupport = e.support
        it.weNote = e.note
        it.weFolder = e.folder
        it.weMainFile = e.mainFile
        it.weFallback = e.fallbackPreview
        it.weProps = e.userPropertiesJSON
        it.weNeedsConversion = e.needsConversion
        if let p = previous?.thumbPath, FileManager.default.fileExists(atPath: p) { it.thumbPath = p }
        else if let pv = e.previewFile { it.thumbPath = await Media.thumbnail(pv, .image, id: e.id) }
        else if let r = ready, kind == .video { it.thumbPath = await Media.thumbnail(r, .video, id: e.id) }
        if it.width == 0, let r = ready, kind == .video, let d = await Media.dims(r, .video) { it.width = d.0; it.height = d.1 }
        return it
    }

    /// A ready-to-show assignment, converting WebM etc. to HEVC first if needed. Nil (with a message) when it can't play on Mac.
    func assignment(for item: WallItem) async -> Assignment? {
        switch item.weSupport {
        case .web?:
            guard let f = item.weMainFile, FileManager.default.fileExists(atPath: f) else { flash?("The web page for “\(item.title)” is missing"); return nil }
            return Assignment(itemID: item.id, title: item.title, path: f, kind: .web, webProps: item.weProps)
        case .video?:
            guard let f = item.weMainFile, FileManager.default.fileExists(atPath: f) else { flash?("The video for “\(item.title)” is missing"); return nil }
            if item.weNeedsConversion ?? false {
                guard let c = await convert(item, from: f) else { return nil }
                return Assignment(itemID: item.id, title: item.title, path: c, kind: .video)
            }
            return Assignment(itemID: item.id, title: item.title, path: f, kind: .video)
        default:
            if let pv = item.weFallback, Pref.weScenePreviews {
                guard let c = await convert(item, from: pv) else { return nil }
                flash?("Showing the animated preview of “\(item.title)”. This is not the real scene, which needs Wallpaper Engine's renderer.")
                return Assignment(itemID: item.id, title: item.title + " (preview)", path: c, kind: .video)
            }
            flash?("“\(item.title)”: \(item.weNote ?? "not playable on Mac")")
            return nil
        }
    }

    private func convert(_ item: WallItem, from src: String) async -> String? {
        let dst = Self.cachePath(item.id)
        if FileManager.default.fileExists(atPath: dst.path) { return dst.path }
        if (src as NSString).pathExtension.lowercased() == "mp4" || (src as NSString).pathExtension.lowercased() == "mov" { return src }
        converting.insert(item.id)
        flash?("Converting “\(item.title)” to HEVC (one time)…")
        defer { converting.remove(item.id) }
        do {
            try await Transcoder.toHEVC(URL(fileURLWithPath: src), dst)
            if let i = items.firstIndex(where: { $0.id == item.id }), item.weSupport == .video {
                items[i].localPath = dst.path
                if let d = await Media.dims(dst.path, .video) { items[i].width = d.0; items[i].height = d.1 }
            }
            return dst.path
        } catch {
            flash?("Couldn't convert “\(item.title)”: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: FSEvents watcher (recursive, coalesced, 2 s latency)

    private func restartWatcher() {
        if let s = stream { FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s); stream = nil }
        let paths = roots.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let me = Unmanaged<WELibrary>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { me.changed() }
        }
        guard let s = FSEventStreamCreate(nil, cb, &ctx, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }

    private func changed() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.rescan() } }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
    }
}
