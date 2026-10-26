// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Live previews in the app: a card plays its clip on hover/focus, the Home hero and the detail sheet autoplay.
// Cheap by design: only clips already on this Mac (no network), a small short copy is made once and cached
// (640×360 for cards, 1280×720 for the hero/detail, first few seconds, no audio), at most 3 players exist,
// and every player stops when the Lucid window is hidden or in the background, Reduce Motion is on, or the
// wallpaper is smart-paused (battery, Low Power, heat, CPU…).
import SwiftUI
import AppKit
import AVFoundation
import Combine

// MARK: - Who may play

@MainActor final class PreviewCenter: ObservableObject {
    static let shared = PreviewCenter()
    static let capacity = 3

    @Published private(set) var active: Set<String> = []
    @Published private(set) var allowed = false
    private var slots = PreviewSlots(capacity: capacity)
    private var pause: PauseReason?
    private var attached = false
    private var observers: [NSObjectProtocol] = []
    private var sink: AnyCancellable?
    /// Used by the dev check: how many players a newer request has taken over so far.
    private(set) var evictions = 0
    /// Used by the dev check only: play although the check runs in the background.
    var checkAlwaysAllow = false { didSet { refresh() } }

    /// Called once the main window exists (ContentView.onAppear). Until then nothing plays.
    func attach(_ engine: LucidEngine) {
        guard !attached else { refresh(); return }
        attached = true
        sink = engine.$pauseKind.sink { [weak self] k in
            MainActor.assumeIsolated { self?.pause = k; self?.refresh() }
        }
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                                          NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                                          NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                                          NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification]
        for n in names {
            observers.append(nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSoon() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        refresh()
    }

    /// Ask for a player. Pinned = the hero or the detail sheet (never taken by a hover).
    @discardableResult func request(_ token: String, pinned: Bool = false) -> Bool {
        let r = slots.request(token, pinned: pinned)
        evictions += r.evicted.count
        publish()
        return r.granted
    }
    func release(_ token: String) {
        guard slots.isActive(token) else { return }
        slots.release(token)
        publish()
    }
    private func publish() { let a = Set(slots.active); if a != active { active = a } }

    private func refreshSoon() { DispatchQueue.main.async { [weak self] in self?.refresh() } }
    /// Development only (needs LUCID_SUPPORT_DIR too): play even when Lucid isn't the frontmost app, so CPU/memory can
    /// be measured without taking focus from the person using the Mac. Reduce Motion and smart pause still apply.
    private static let devIgnoreFocus = ProcessInfo.processInfo.environment["LUCID_DEV_PREVIEW_ALWAYS"] == "1"
        && ProcessInfo.processInfo.environment["LUCID_SUPPORT_DIR"] != nil

    func refresh() {
        let ok = checkAlwaysAllow || attached && PreviewPolicy.shouldPlay(windowVisible: Self.devIgnoreFocus || Self.windowVisible(),
                                                      appActive: Self.devIgnoreFocus || NSApp.isActive,
                                                      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, pause: pause)
        _ = slots.setEnabled(ok)
        if ok != allowed { allowed = ok }
        publish()
    }
    /// A Lucid window (not a wallpaper window, not a menu) is on screen and not fully covered.
    private static func windowVisible() -> Bool {
        NSApp.windows.contains { w in
            !(w is WallpaperWindow) && w.isVisible && !w.isMiniaturized && w.styleMask.contains(.titled) && w.occlusionState.contains(.visible)
        }
    }
    /// Used by the dev check: how many preview players exist right now.
    var activeCount: Int { slots.active.count }
}

// MARK: - Small cached copies

enum PreviewSize {
    case small, large
    var preset: String { self == .small ? AVAssetExportPreset640x480 : AVAssetExportPreset1280x720 }
    var seconds: Double { self == .small ? 8 : 12 }
    var tag: String { self == .small ? "s" : "l" }
    /// Size budget per copy (about 2 Mbit/s small, 4 Mbit/s large).
    var maxBytes: Int64 { self == .small ? 2_000_000 : 6_000_000 }
}

@MainActor final class PreviewRenditions {
    static let shared = PreviewRenditions()
    static let maxFiles = 160
    static let maxTotalBytes: Int64 = 300_000_000
    static var dir: URL { Paths.make(Paths.support.appendingPathComponent("Previews", isDirectory: true)) }
    private var busy = false

    static func file(id: String, size: PreviewSize) -> URL { dir.appendingPathComponent("\(Paths.safe(id))-\(size.tag).mp4") }

    /// A short, small, silent copy of a clip on this Mac, made once (one at a time) and reused. nil if the source
    /// isn't a readable local video, or the caller stopped waiting (the card scrolled away or lost hover).
    func url(source: String, id: String, size: PreviewSize) async -> URL? {
        let out = Self.file(id: id, size: size)
        if Self.fresh(out, source) { return out }
        guard FileManager.default.isReadableFile(atPath: source) else { return nil }
        while busy {
            if Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if Task.isCancelled { return nil }
        if Self.fresh(out, source) { return out }
        busy = true
        defer { busy = false }
        let made = await Self.export(source, to: out, size: size)
        if made != nil { Self.prune() }
        return made
    }

    /// Delete the cached copies of a removed wallpaper.
    static func forget(id: String) {
        for s in [PreviewSize.small, .large] { try? FileManager.default.removeItem(at: file(id: id, size: s)) }
    }

    private static func fresh(_ out: URL, _ source: String) -> Bool {
        let fm = FileManager.default
        guard let o = (try? fm.attributesOfItem(atPath: out.path))?[.modificationDate] as? Date else { return false }
        let s = (try? fm.attributesOfItem(atPath: source))?[.modificationDate] as? Date ?? .distantPast
        return o >= s
    }

    private nonisolated static func export(_ source: String, to out: URL, size: PreviewSize) async -> URL? {
        let fm = FileManager.default
        let asset = AVURLAsset(url: URL(fileURLWithPath: source))
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let duration = try? await asset.load(.duration), duration.seconds > 0 else { return nil }
        let comp = AVMutableComposition()
        guard let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: min(size.seconds, duration.seconds), preferredTimescale: 600))
        do { try ct.insertTimeRange(range, of: track, at: .zero) } catch { return nil }
        ct.preferredTransform = (try? await track.load(.preferredTransform)) ?? .identity
        guard let ex = AVAssetExportSession(asset: comp, presetName: size.preset) else { return nil }
        let tmp = out.deletingLastPathComponent().appendingPathComponent(".partial-" + out.lastPathComponent)
        try? fm.removeItem(at: tmp)
        ex.outputURL = tmp
        ex.outputFileType = .mp4
        ex.fileLengthLimit = size.maxBytes
        let box = ExportBox(ex)
        // The card scrolled away or lost hover: stop making the copy.
        await withTaskCancellationHandler { await box.run() } onCancel: { box.cancel() }
        guard !Task.isCancelled, box.session.status == .completed else { try? fm.removeItem(at: tmp); return nil }
        try? fm.removeItem(at: out)
        do { try fm.moveItem(at: tmp, to: out) } catch { try? fm.removeItem(at: tmp); return nil }
        return out
    }

    /// Keep the cache bounded (file count and total size): oldest copies go first. Only regular `.mp4` files (the
    /// copies) are counted or deleted; anything else in the folder is left alone.
    static func prune(in folder: URL? = nil) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let all = try? fm.contentsOfDirectory(at: folder ?? dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
        let files = all.filter { u in
            let v = try? u.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return v?.isRegularFile == true && v?.isSymbolicLink != true && u.pathExtension.lowercased() == "mp4"
        }
        var dated = files.map { u -> (URL, Date, Int64) in
            let v = try? u.resourceValues(forKeys: Set(keys))
            return (u, v?.contentModificationDate ?? .distantPast, Int64(v?.fileSize ?? 0))
        }.sorted { $0.1 < $1.1 }
        var total = dated.reduce(Int64(0)) { $0 + $1.2 }
        while !dated.isEmpty && (dated.count > maxFiles || total > maxTotalBytes) {
            let (u, _, n) = dated.removeFirst()
            try? fm.removeItem(at: u); total -= n
        }
    }
}

// MARK: - The player view

/// A muted, looping, aspect-filled video that fades in over the poster once its first frame is ready.
struct LoopingPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PreviewPlayerView { let v = PreviewPlayerView(); v.load(url); return v }
    func updateNSView(_ v: PreviewPlayerView, context: Context) { if v.url != url { v.load(url) } }
    static func dismantleNSView(_ v: PreviewPlayerView, coordinator: ()) { v.unload() }
}

final class PreviewPlayerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var ready: NSKeyValueObservation?
    private(set) var url: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.opacity = 0
        layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
    func load(_ u: URL) {
        unload()
        url = u
        let p = AVQueuePlayer()
        p.isMuted = true
        p.preventsDisplaySleepDuringVideoPlayback = false
        p.allowsExternalPlayback = false
        let item = AVPlayerItem(url: u)
        item.preferredForwardBufferDuration = 2
        looper = AVPlayerLooper(player: p, templateItem: item)
        player = p
        playerLayer.player = p
        ready = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] l, _ in
            guard l.isReadyForDisplay else { return }
            DispatchQueue.main.async { self?.fadeIn() }
        }
        p.play()
    }
    private func fadeIn() {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = playerLayer.presentation()?.opacity ?? 0
        a.toValue = 1
        a.duration = 0.35
        playerLayer.opacity = 1
        playerLayer.add(a, forKey: "fade")
    }
    func unload() {
        ready = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        playerLayer.player = nil
        player = nil
        playerLayer.opacity = 0
        url = nil
    }
}

// MARK: - Hooking a view up

/// Shared behaviour for anything that previews: asks for a slot while `wanted`, fetches the small copy, shows the
/// player over whatever poster sits underneath, and lets go on hide/scroll-away.
struct PreviewLayer: View {
    let item: WallItem
    let wanted: Bool
    var pinned = false
    var size: PreviewSize = .small
    var dwell: Double = 0.35
    @ObservedObject var center = PreviewCenter.shared   // the dev check passes its own
    @State private var token = UUID().uuidString
    @State private var url: URL?

    private var source: String? {
        guard let p = PreviewPolicy.previewPath(item), FileManager.default.fileExists(atPath: p) else { return nil }
        return p
    }
    private var isActive: Bool { center.active.contains(token) }

    var body: some View {
        ZStack {
            if isActive, let url { LoopingPreview(url: url).transition(.opacity).allowsHitTesting(false) }
        }
        // Ask for a player when this starts wanting one (or its clip changes). Losing the player to a newer hover
        // does not ask again (two hovers would otherwise take it from each other forever); hovering again does.
        .task(id: RequestKey(id: item.id, source: source, wanted: wanted, allowed: center.allowed)) {
            guard wanted, center.allowed, source != nil else { center.release(token); return }
            guard !isActive else { return }
            if dwell > 0 { try? await Task.sleep(nanoseconds: UInt64(dwell * 1_000_000_000)) }
            guard !Task.isCancelled, wanted else { return }
            center.request(token, pinned: pinned)
        }
        // Load the clip while holding a player; a different item or a newly downloaded file loads afresh.
        .task(id: LoadKey(id: item.id, source: source, active: isActive)) {
            url = nil
            guard isActive, let s = source else { return }
            let u = Self.devOriginal ? URL(fileURLWithPath: s) : await PreviewRenditions.shared.url(source: s, id: item.id, size: size)
            if !Task.isCancelled { url = u }
        }
        .onDisappear { center.release(token); url = nil }
        .accessibilityHidden(true)
    }
    private struct RequestKey: Equatable { let id: String; let source: String?; let wanted: Bool; let allowed: Bool }
    private struct LoadKey: Equatable { let id: String; let source: String?; let active: Bool }
    /// Development only (with LUCID_SUPPORT_DIR): play the full 4K file instead of the small copy, to measure the difference.
    private static let devOriginal = ProcessInfo.processInfo.environment["LUCID_DEV_PREVIEW_ORIGINAL"] == "1"
        && ProcessInfo.processInfo.environment["LUCID_SUPPORT_DIR"] != nil
}
