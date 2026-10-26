// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// One borderless desktop-level window per display (see Surfaces.swift), with what each display shows
// resolved from plain assignments and Day/Night rules. Changes cross-fade; old players are released.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

@MainActor final class LucidEngine: ObservableObject {
    @Published private(set) var state = EngineState()
    @Published private(set) var pauseReason: String?
    @Published private(set) var tick = 0
    private(set) var surfaces: [String: ScreenSurface] = [:]
    private var fading: [ScreenSurface] = []
    private var locked = false, asleep = false, onBattery = false, lowPower = false
    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []
    static let crossfade: TimeInterval = 1.2
    /// Off only in the headless dev check, so it never changes your real desktop picture.
    static var setsDesktopPicture = true

    /// Current day/night phase (set by DayNightController).
    var phase: () -> DayPhase = { .day }
    /// Called when audio capture becomes needed / not needed (some running wallpaper reacts to sound).
    var onAudioNeedChanged: ((Bool) -> Void)?
    private(set) var audioNeeded = false

    init() {
        if let d = try? Data(contentsOf: Paths.state), let s = SavedData.state(d) { state = s }
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        checkBattery()
        observe()
    }

    // MARK: Resolving what each display shows

    /// The Day/Night rule governing a display, and its scope key (display key or "*").
    func rule(for screen: NSScreen) -> (rule: DayNightRule, scope: String)? {
        let k = screen.stableKey
        if let r = state.dayNight?[k] { return (r, k) }
        if state.perScreen[k] != nil { return nil }
        if let r = state.dayNight?[EngineState.allKey] { return (r, EngineState.allKey) }
        return nil
    }
    var hasDayNightRules: Bool { !(state.dayNight ?? [:]).isEmpty }

    func assignment(for screen: NSScreen) -> Assignment? {
        if let r = rule(for: screen) { return r.rule.pick(phase()) }
        return state.perScreen[screen.stableKey] ?? state.all
    }
    var currentAssignments: [Assignment] { NSScreen.screens.compactMap(assignment(for:)) }

    func isPlaying(_ screen: NSScreen) -> Bool { surfaces[screen.stableKey]?.isRunning ?? false }
    func screenPaused(_ screen: NSScreen) -> String? {
        guard let p = surfaces[screen.stableKey] else { return nil }
        if let r = pauseReason { return r }
        if Pref.pauseWhenCovered && !p.visible { return "Covered by a window/full-screen app" }
        return nil
    }

    private func save() { if let d = try? JSONEncoder().encode(state) { try? d.write(to: Paths.state, options: .atomic) } }

    // MARK: Changing assignments

    func apply(_ a: Assignment, screenKey: String?) {
        if let k = screenKey { state.perScreen[k] = a; state.dayNight?[k] = nil }
        else { state.all = a; state.perScreen = [:]; state.dayNight = nil }
        state.userPaused = false
        save()
        refresh()
        setDesktopPicture(a, NSScreen.screens.filter { screenKey == nil || $0.stableKey == screenKey })
    }

    func applyDayNight(_ r: DayNightRule, screenKey: String?) {
        if let k = screenKey { state.perScreen[k] = nil; state.dayNight = (state.dayNight ?? [:]).merging([k: r]) { $1 } }
        else { state.all = nil; state.perScreen = [:]; state.dayNight = [EngineState.allKey: r] }
        state.userPaused = false
        save()
        refresh()
        updateDesktopPictures()
    }

    func clear(screenKey: String?) {
        if let k = screenKey {
            if state.dayNight?[k] != nil { state.dayNight?[k] = nil }
            else if state.perScreen[k] != nil { state.perScreen[k] = nil }
            else {
                // Screen was following "all": keep the others, blank this one by pinning others explicitly.
                let allRule = state.dayNight?[EngineState.allKey]
                for s in NSScreen.screens where s.stableKey != k && state.perScreen[s.stableKey] == nil && state.dayNight?[s.stableKey] == nil {
                    if let all = state.all { state.perScreen[s.stableKey] = all }
                    else if let r = allRule { state.dayNight?[s.stableKey] = r }
                }
                state.all = nil
                state.dayNight?[EngineState.allKey] = nil
            }
        } else { state.all = nil; state.perScreen = [:]; state.dayNight = nil }
        save(); refresh()
    }

    func forget(path: String) {
        if state.all?.path == path { state.all = nil }
        state.perScreen = state.perScreen.filter { $0.value.path != path }
        state.dayNight = state.dayNight?.filter { $0.value.day.path != path && $0.value.night.path != path }
        save(); refresh()
    }

    /// Audio-reactive look options for whatever governs this display (its own assignment or the shared one).
    func reactive(for screen: NSScreen) -> ReactiveOptions { assignment(for: screen)?.reactive ?? ReactiveOptions() }
    func setReactive(_ o: ReactiveOptions, for screen: NSScreen) {
        let k = screen.stableKey
        let v: ReactiveOptions? = o.any ? o : nil
        if let (r, scope) = rule(for: screen) {
            var n = r; n.day.reactive = v; n.night.reactive = v
            state.dayNight?[scope] = n
        } else if state.perScreen[k] != nil { state.perScreen[k]?.reactive = v }
        else if state.all != nil { state.all?.reactive = v }
        save(); refresh()
    }

    func togglePause() { state.userPaused.toggle(); save(); updatePlayback() }
    func applyLook() {
        for s in surfaces.values { s.applyLook() }
        updatePlayback()
    }

    /// Day/Night phase changed (or the clock/time zone did): show the right wallpaper with a cross-fade.
    func phaseDidChange() {
        guard hasDayNightRules else { return }
        refresh()
        updateDesktopPictures()
    }

    // MARK: Desktop picture (shown in Mission Control, other Spaces and after quitting)

    private func setDesktop(_ url: URL, _ screen: NSScreen) {
        try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
            .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
            .allowClipping: NSNumber(value: true)])
    }
    private func setDesktopPicture(_ a: Assignment, _ targets: [NSScreen]) {
        guard Self.setsDesktopPicture else { return }
        switch a.kind {
        case .image: targets.forEach { setDesktop(URL(fileURLWithPath: a.path), $0) }
        case .video: Task { if let poster = await Media.poster(a) { targets.forEach { self.setDesktop(poster, $0) } } }
        }
    }
    private func updateDesktopPictures() {
        for s in NSScreen.screens where rule(for: s) != nil {
            if let a = assignment(for: s) { setDesktopPicture(a, [s]) }
        }
    }

    // MARK: Windows

    /// Video always needs a window; a still image needs one only for audio-reactive looks or Day/Night cross-fades.
    private func needsSurface(_ a: Assignment, _ screen: NSScreen) -> Bool {
        switch a.kind {
        case .video: return true
        case .image: return (a.reactive?.any ?? false) || rule(for: screen) != nil
        }
    }

    func refresh() {
        var wanted: [String: (NSScreen, Assignment)] = [:]
        for s in NSScreen.screens {
            if let a = assignment(for: s), needsSurface(a, s), FileManager.default.fileExists(atPath: a.path) { wanted[s.stableKey] = (s, a) }
        }
        for (k, p) in surfaces where wanted[k] == nil { p.close(); surfaces[k] = nil }
        for (k, (s, a)) in wanted {
            if let p = surfaces[k], p.assignment.sameMedia(a) {
                p.move(to: s)
                if p.assignment != a { p.update(a) }
                continue
            }
            let old = surfaces[k]
            let n = ScreenSurface(screen: s, key: k, assignment: a)
            surfaces[k] = n
            n.occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: n.window, queue: .main) { [weak self, weak n] _ in
                MainActor.assumeIsolated {
                    guard let n else { return }
                    n.visible = n.window.occlusionState.contains(.visible)
                    self?.updatePlayback()
                }
            }
            if let old { crossfade(from: old, to: n) }
        }
        updatePlayback()
    }

    private func crossfade(from old: ScreenSurface, to new: ScreenSurface) {
        if let o = old.occlusionObserver { NotificationCenter.default.removeObserver(o); old.occlusionObserver = nil }
        fading.append(old)
        new.window.isOpaque = false
        new.window.alphaValue = 0
        new.window.order(.above, relativeTo: old.window.windowNumber)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.crossfade
            new.window.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                new.window.isOpaque = true
                old.close()
                self?.fading.removeAll { $0 === old }
            }
        })
    }

    func updatePlayback() {
        var reason: String?
        if state.userPaused { reason = "Paused" }
        else if locked { reason = "Screen locked" }
        else if asleep { reason = "Display asleep" }
        else if Pref.pauseOnBattery && onBattery { reason = "On battery" }
        else if Pref.pauseLowPower && lowPower { reason = "Low Power Mode" }
        pauseReason = reason
        var needAudio = false
        for s in surfaces.values {
            let covered = Pref.pauseWhenCovered && !s.visible
            let run = reason == nil && !covered
            s.setRunning(run)
            if run && (s.assignment.reactive?.any ?? false) { needAudio = true }
        }
        if needAudio != audioNeeded {
            audioNeeded = needAudio
            if !needAudio { surfaces.values.forEach { $0.resetReactive() } }
            onAudioNeedChanged?(needAudio)
        }
        tick += 1
    }

    /// Latest (smoothed) audio frame, ~30 times a second while capture runs.
    func deliverAudio(_ frame: AudioFrame) {
        for s in surfaces.values where s.isRunning { s.deliver(frame) }
    }
    func resetAudioLooks() { surfaces.values.forEach { $0.resetReactive() } }

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
    func writeStatus(force: Bool = false) {
        guard Pref.writeStatus || force else { return }
        var screens: [[String: Any]] = []
        for s in NSScreen.screens {
            var row: [String: Any] = ["name": s.localizedName, "key": s.stableKey, "pixels": s.pixelSize,
                                      "assignment": assignment(for: s)?.title ?? NSNull(),
                                      "dayNight": rule(for: s) != nil]
            if let p = surfaces[s.stableKey] {
                row["windowNumber"] = p.window.windowNumber
                row["kind"] = p.assignment.kind.rawValue
                row["running"] = p.isRunning
                if let pl = p.player { row["rate"] = pl.rate; row["time"] = pl.currentTime().seconds }
                row["dim"] = Pref.dim
                row["visible"] = p.visible
                row["reactive"] = p.assignment.reactive?.any ?? false
                row["path"] = p.assignment.path
            }
            screens.append(row)
        }
        let j: [String: Any] = ["at": Date().timeIntervalSince1970, "pauseReason": pauseReason ?? NSNull(),
                                "onBattery": onBattery, "lowPower": lowPower, "locked": locked, "phase": phase().rawValue,
                                "audioNeeded": audioNeeded, "fading": fading.count, "screens": screens]
        if let d = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: Paths.status) }
    }
}
