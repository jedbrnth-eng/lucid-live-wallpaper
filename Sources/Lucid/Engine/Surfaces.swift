// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// What sits in each desktop window: a looping video or a still image,
// plus the optional audio-reactive look layers (pulse, glow, spectrum bars) and the dim layer.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import ImageIO

// MARK: - Screens

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
    var stableKey: String {
        if let u = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() { return CFUUIDCreateString(nil, u) as String }
        return "display-\(displayID)"
    }
    var pixelSize: String { "\(Int(frame.width * backingScaleFactor))×\(Int(frame.height * backingScaleFactor))" }
}

// MARK: - Window

/// In a headless development run (Headless.swift) these windows are built and played into but never put on screen:
/// every way of ordering one in is refused here, so no code path (a new wallpaper, a cross-fade) can draw.
final class WallpaperWindow: NSWindow {
    /// Wallpaper windows made and not yet closed (the dev check counts what a change left behind).
    private(set) static var open = 0
    private var counted = true

    init(screen: NSScreen) {
        WallpaperWindow.open += 1
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        canHide = false  // keep playing when the user hides Lucid (⌘H)
        isReleasedWhenClosed = false
        animationBehavior = .none
        title = "Lucid Desktop"
        setFrame(screen.frame, display: false)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func orderFrontRegardless() { if !Headless.active { super.orderFrontRegardless() } }
    override func order(_ place: NSWindow.OrderingMode, relativeTo other: Int) {
        if Headless.active && place != .out { return }
        super.order(place, relativeTo: other)
    }
    override func close() {
        if counted { counted = false; WallpaperWindow.open -= 1 }
        super.close()
    }
}

// MARK: - Layer host for video and image wallpapers

final class SurfaceHostView: NSView {
    let contentLayer: CALayer
    let glowLayer = CAGradientLayer()
    let barsLayer = CAShapeLayer()
    let dimLayer = CALayer()
    private var lastBars: [Float] = []
    /// Per-wallpaper fit and crop focus (nil fields = app-wide setting) and the media's pixel size once known.
    var options = WallpaperOptions() { didSet { applyLook() } }
    var mediaSize: CGSize? { didSet { needsLayout = true } }

    init(content: CALayer) {
        contentLayer = content
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        layer?.addSublayer(contentLayer)
        glowLayer.type = .radial
        glowLayer.colors = [NSColor.white.withAlphaComponent(0.9).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1.1, y: 1.1)
        glowLayer.opacity = 0
        layer?.addSublayer(glowLayer)
        barsLayer.fillColor = NSColor(red: 0, green: 0.94, blue: 1, alpha: 0.55).cgColor
        barsLayer.isHidden = true
        layer?.addSublayer(barsLayer)
        dimLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(dimLayer)
        applyLook()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // bounds + position (not frame) so the pulse transform scales around the centre.
        let r = contentFrame()
        contentLayer.bounds = CGRect(origin: .zero, size: r.size)
        contentLayer.position = CGPoint(x: r.midX, y: r.midY)
        glowLayer.frame = bounds; barsLayer.frame = bounds; dimLayer.frame = bounds
        CATransaction.commit()
        if !lastBars.isEmpty { drawBars(lastBars) }
    }

    /// Where the media sits: computed from its size (fill with crop focus, fit, stretch) once known, else the whole screen.
    private func contentFrame() -> CGRect {
        guard let m = mediaSize, m.width > 0, m.height > 0 else { return bounds }
        let f = FillLayout.frame(media: (Double(m.width), Double(m.height)), bounds: (Double(bounds.width), Double(bounds.height)),
                                 mode: options.effectiveFit(defaultFill: Pref.fillScreen), focusX: options.focusX ?? 0.5, focusY: options.focusY ?? 0.5)
        return CGRect(x: f.x, y: f.y, width: f.w, height: f.h)
    }

    func applyLook() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let fit = options.effectiveFit(defaultFill: Pref.fillScreen)
        // With a known media size the frame already has the right aspect, so the layer just fills it.
        let known = (mediaSize?.width ?? 0) > 0
        if let p = contentLayer as? AVPlayerLayer {
            p.videoGravity = known || fit == .stretch ? .resize : fit == .fill ? .resizeAspectFill : .resizeAspect
        } else {
            contentLayer.contentsGravity = known || fit == .stretch ? .resize : fit == .fill ? .resizeAspectFill : .resizeAspect
        }
        dimLayer.opacity = Float(min(0.8, max(0, Pref.dim)))
        CATransaction.commit()
        needsLayout = true
    }

    func applyReactive(_ look: ReactiveLook) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let s = CGFloat(look.scale)
        contentLayer.transform = s == 1 ? CATransform3DIdentity : CATransform3DMakeScale(s, s, 1)
        glowLayer.opacity = look.glow
        barsLayer.isHidden = look.bars.isEmpty
        if !look.bars.isEmpty { drawBars(look.bars) }
        lastBars = look.bars
        CATransaction.commit()
    }

    private func drawBars(_ bars: [Float]) {
        let w = bounds.width, h = bounds.height * 0.16, n = CGFloat(bars.count)
        guard w > 0, n > 0 else { return }
        let slot = w / n, barW = slot * 0.62
        let path = CGMutablePath()
        for (i, v) in bars.enumerated() {
            let bh = max(2, CGFloat(v) * h)
            path.addRoundedRect(in: CGRect(x: CGFloat(i) * slot + (slot - barW) / 2, y: 0, width: barW, height: bh),
                                cornerWidth: min(barW / 2, 3), cornerHeight: min(barW / 2, 3))
        }
        barsLayer.path = path
    }
}

// MARK: - One display's wallpaper

@MainActor final class ScreenSurface {
    let key: String
    private(set) var assignment: Assignment
    let window: WallpaperWindow
    private(set) var host: SurfaceHostView?
    /// The looping player this window shows, shared with every other window showing the same file at the same speed.
    private(set) var player: AVQueuePlayer?
    /// The speed this window's player was made for. A new speed means a new window (LucidEngine.refresh cross-fades).
    let playSpeed: Double
    private let holder = UUID().uuidString
    private(set) var wantsRun = false
    var visible = true
    var occlusionObserver: NSObjectProtocol?

    /// Effective playback speed of an assignment (its own speed, else the app-wide one).
    static func speed(of a: Assignment) -> Double { (a.options ?? WallpaperOptions()).effectiveSpeed(default: Pref.speed) }

    init(screen: NSScreen, key: String, assignment: Assignment) {
        self.key = key
        self.assignment = assignment
        playSpeed = Self.speed(of: assignment)
        window = WallpaperWindow(screen: screen)
        switch assignment.kind {
        case .video:
            let p = SharedPlayers.shared.acquire(path: assignment.path, speed: playSpeed, holder: holder)
            player = p
            let l = AVPlayerLayer(); l.player = p
            host = SurfaceHostView(content: l)
            window.contentView = host
            let path = assignment.path
            Task { [weak self] in
                if let d = await Media.dims(path, .video) { self?.host?.mediaSize = CGSize(width: d.0, height: d.1) }
            }
        case .image:
            let l = CALayer()
            let maxPixels = max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor
            let img = Self.loadImage(assignment.path, maxPixels: maxPixels)
            l.contents = img
            host = SurfaceHostView(content: l)
            if let img { host?.mediaSize = CGSize(width: img.width, height: img.height) }
            window.contentView = host
        }
        host?.options = assignment.options ?? WallpaperOptions()
        applyLook()
        window.orderFrontRegardless()
    }

    /// This window's video is playing (a shared player may also run for another display while this one is covered).
    var isRunning: Bool {
        if let p = player { return wantsRun && p.rate > 0 }
        return true
    }
    /// Whether this window can keep showing `a` as it is: same media, and for a video the same speed.
    func canShow(_ a: Assignment) -> Bool { assignment.sameMedia(a) && (a.kind != .video || Self.speed(of: a) == playSpeed) }

    private static func loadImage(_ path: String, maxPixels: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                            kCGImageSourceThumbnailMaxPixelSize: max(640, maxPixels),
                                                            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
    }

    func move(to screen: NSScreen) {
        if window.frame != screen.frame { window.setFrame(screen.frame, display: true) }
    }

    /// Look options changed but the media and speed did not: update in place, no reload.
    func update(_ a: Assignment) {
        assignment = a
        if !(a.reactive?.any ?? false) { host?.applyReactive(ReactiveLook()) }
        let o = a.options ?? WallpaperOptions()
        if host?.options != o { host?.options = o }
    }

    func applyLook() { host?.applyLook() }

    func setRunning(_ run: Bool) {
        wantsRun = run
        if player != nil { SharedPlayers.shared.setRunning(run, path: assignment.path, speed: playSpeed, holder: holder) }
    }

    func deliver(_ frame: AudioFrame) {
        if let o = assignment.reactive, o.any { host?.applyReactive(ReactiveMapper.look(frame, options: o)) }
    }

    func resetReactive() { host?.applyReactive(ReactiveLook()) }

    func close() {
        if let o = occlusionObserver { NotificationCenter.default.removeObserver(o); occlusionObserver = nil }
        if player != nil { SharedPlayers.shared.release(path: assignment.path, speed: playSpeed, holder: holder) }
        player = nil
        window.orderOut(nil)
        window.contentView = nil
        host = nil
        window.close()
    }
}
