// One borderless desktop-level window with a looping player per display.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
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

// MARK: - Wallpaper engine (one borderless desktop-level window + looping AVPlayer per display)

final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        title = "Lucid Desktop"
        setFrame(screen.frame, display: false)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PlayerHostView: NSView {
    let playerLayer = AVPlayerLayer()
    let dimLayer = CALayer()
    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(dimLayer)
        applyLook()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); playerLayer.frame = bounds; dimLayer.frame = bounds }
    func applyLook() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        playerLayer.videoGravity = Pref.fillScreen ? .resizeAspectFill : .resizeAspect
        dimLayer.opacity = Float(min(0.8, max(0, Pref.dim)))
        CATransaction.commit()
    }
}

@MainActor final class ScreenPlayer {
    let key: String
    let assignment: Assignment
    let window: WallpaperWindow
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private(set) var host: PlayerHostView!
    var visible = true

    init(screen: NSScreen, key: String, assignment: Assignment) {
        self.key = key
        self.assignment = assignment
        window = WallpaperWindow(screen: screen)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        let item = AVPlayerItem(url: URL(fileURLWithPath: assignment.path))
        item.preferredForwardBufferDuration = 2
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.defaultRate = Float(Pref.speed)
        host = PlayerHostView(player: player)
        window.contentView = host
        window.orderFrontRegardless()
    }
    func move(to screen: NSScreen) {
        if window.frame != screen.frame { window.setFrame(screen.frame, display: true) }
    }
    func close() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
}

@MainActor final class WallpaperEngine: ObservableObject {
    @Published private(set) var state = EngineState()
    @Published private(set) var pauseReason: String?
    @Published private(set) var tick = 0
    private(set) var players: [String: ScreenPlayer] = [:]
    private var locked = false, asleep = false, onBattery = false, lowPower = false
    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        if let d = try? Data(contentsOf: Paths.state), let s = try? JSONDecoder().decode(EngineState.self, from: d) { state = s }
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        checkBattery()
        observe()
    }

    func assignment(for screen: NSScreen) -> Assignment? { state.perScreen[screen.stableKey] ?? state.all }
    func isPlaying(_ screen: NSScreen) -> Bool { (players[screen.stableKey]?.player.rate ?? 0) > 0 }
    func screenPaused(_ screen: NSScreen) -> String? {
        guard let p = players[screen.stableKey] else { return nil }
        if let r = pauseReason { return r }
        if Pref.pauseWhenCovered && !p.visible { return "Covered by a window/full-screen app" }
        return nil
    }

    private func save() { if let d = try? JSONEncoder().encode(state) { try? d.write(to: Paths.state, options: .atomic) } }

    func apply(_ a: Assignment, screenKey: String?) {
        if let k = screenKey { state.perScreen[k] = a } else { state.all = a; state.perScreen = [:] }
        state.userPaused = false
        save()
        refresh()
        let targets = NSScreen.screens.filter { screenKey == nil || $0.stableKey == screenKey }
        if a.kind == .image {
            targets.forEach { setDesktop(URL(fileURLWithPath: a.path), $0) }
        } else {
            Task { if let poster = await Media.poster(a) { targets.forEach { self.setDesktop(poster, $0) } } }
        }
    }

    func clear(screenKey: String?) {
        if let k = screenKey {
            if state.perScreen[k] != nil { state.perScreen[k] = nil }
            else if let all = state.all {
                // Screen was following "all": keep the others, blank this one by pinning others explicitly.
                for s in NSScreen.screens where s.stableKey != k { state.perScreen[s.stableKey] = state.perScreen[s.stableKey] ?? all }
                state.all = nil
            }
        } else { state.all = nil; state.perScreen = [:] }
        save(); refresh()
    }

    func forget(path: String) {
        if state.all?.path == path { state.all = nil }
        state.perScreen = state.perScreen.filter { $0.value.path != path }
        save(); refresh()
    }

    func togglePause() { state.userPaused.toggle(); save(); updatePlayback() }
    func applyLook() {
        for p in players.values { p.host.applyLook(); p.player.defaultRate = Float(Pref.speed) }
        updatePlayback()
    }

    private func setDesktop(_ url: URL, _ screen: NSScreen) {
        try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
            .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
            .allowClipping: NSNumber(value: true)])
    }

    func refresh() {
        var wanted: [String: (NSScreen, Assignment)] = [:]
        for s in NSScreen.screens {
            if let a = assignment(for: s), a.kind == .video, FileManager.default.fileExists(atPath: a.path) { wanted[s.stableKey] = (s, a) }
        }
        for (k, p) in players where wanted[k] == nil || wanted[k]!.1 != p.assignment { p.close(); players[k] = nil }
        for (k, (s, a)) in wanted {
            if let p = players[k] { p.move(to: s) }
            else {
                let p = ScreenPlayer(screen: s, key: k, assignment: a)
                players[k] = p
                let o = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: p.window, queue: .main) { [weak self, weak p] _ in
                    MainActor.assumeIsolated {
                        guard let p else { return }
                        p.visible = p.window.occlusionState.contains(.visible)
                        self?.updatePlayback()
                    }
                }
                observers.append(o)
            }
        }
        updatePlayback()
    }

    func updatePlayback() {
        var reason: String?
        if state.userPaused { reason = "Paused" }
        else if locked { reason = "Screen locked" }
        else if asleep { reason = "Display asleep" }
        else if Pref.pauseOnBattery && onBattery { reason = "On battery" }
        else if Pref.pauseLowPower && lowPower { reason = "Low Power Mode" }
        pauseReason = reason
        for p in players.values {
            let covered = Pref.pauseWhenCovered && !p.visible
            let r = Float(Pref.speed)
            if reason == nil && !covered { if p.player.rate != r { p.player.defaultRate = r; p.player.rate = r } }
            else if p.player.rate != 0 { p.player.pause() }
        }
        tick += 1
    }

    private func checkBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String? else { return }
        let b = type == "Battery Power"
        if b != onBattery { onBattery = b; updatePlayback() }
    }

    private func observe() {
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked = true; self?.updatePlayback() } })
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked = false; self?.updatePlayback() } })
        let wnc = NSWorkspace.shared.notificationCenter
        observers.append(wnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = true; self?.updatePlayback() } })
        observers.append(wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = false; self?.updatePlayback() } })
        observers.append(wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = false; self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled; self?.updatePlayback() } })
        timers.append(Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkBattery() } })
        timers.append(Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeStatus() } })
    }

    /// Diagnostic snapshot (only when `defaults write com.jedbrn.lucid writeStatus -bool YES`).
    func writeStatus() {
        guard Pref.writeStatus else { return }
        var screens: [[String: Any]] = []
        for s in NSScreen.screens {
            var row: [String: Any] = ["name": s.localizedName, "key": s.stableKey, "pixels": s.pixelSize,
                                      "assignment": assignment(for: s)?.title ?? NSNull()]
            if let p = players[s.stableKey] {
                row["windowNumber"] = p.window.windowNumber
                row["rate"] = p.player.rate
                row["gravity"] = p.host.playerLayer.videoGravity.rawValue
                row["dim"] = p.host.dimLayer.opacity
                row["time"] = p.player.currentTime().seconds
                row["visible"] = p.visible
                row["path"] = p.assignment.path
            }
            screens.append(row)
        }
        let j: [String: Any] = ["at": Date().timeIntervalSince1970, "pauseReason": pauseReason ?? NSNull(),
                                "onBattery": onBattery, "lowPower": lowPower, "locked": locked, "screens": screens]
        if let d = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: Paths.status) }
    }
}
