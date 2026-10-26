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
    @Published private(set) var pauseKind: PauseReason?
    /// "Playing" / "Paused: full-screen app" etc., shown in Settings and the menu bar.
    @Published private(set) var statusText = "No wallpaper playing"
    @Published private(set) var tick = 0
    private(set) var surfaces: [String: ScreenSurface] = [:]
    private var fading: [ScreenSurface] = []
    private(set) var power = PowerSnapshot()
    private var cpuGate = CPUGate(thresholdPercent: Pref.cpuAbovePercent, window: 6)
    private var lastTicks: CPUTicks?
    /// When every display became paused for a global reason (nil while playing).
    private(set) var pausedSince: Date?
    /// Players were released after a long pause; rebuilt on resume.
    private(set) var parked = false
    var now: () -> Date = Date.init
    private var timers: [Timer] = []
    private var observers: [NSObjectProtocol] = []
    static let crossfade: TimeInterval = 1.2
    /// Off only in the headless dev check, so it never changes your real desktop picture.
    static var setsDesktopPicture = true

    /// Current day/night phase (set by DayNightController).
    var phase: () -> DayPhase = { .day }
    /// Current four-phase part (dawn/day/dusk/night), set by DayNightController.
    var part: () -> DayPart = { .day }
    /// Called when audio capture becomes needed / not needed (some running wallpaper reacts to sound).
    var onAudioNeedChanged: ((Bool) -> Void)?
    private(set) var audioNeeded = false

    init() {
        if let d = try? Data(contentsOf: Paths.state), let s = SavedData.state(d) { state = s }
        power.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        power.thermal = Self.thermal()
        power.userPaused = state.userPaused
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
        if let r = rule(for: screen) { return r.rule.pick(phase(), part: part()) }
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

    /// `keepScreens`: displays that keep their own wallpaper when one is set for all (per-display playlists).
    func apply(_ a: Assignment, screenKey: String?, keepScreens: Set<String> = []) {
        if let k = screenKey { state.perScreen[k] = a; state.dayNight?[k] = nil }
        else {
            state.all = a
            state.perScreen = state.perScreen.filter { keepScreens.contains($0.key) }
            state.dayNight = keepScreens.isEmpty ? nil : state.dayNight?.filter { keepScreens.contains($0.key) }
        }
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
        state.dayNight = state.dayNight?.filter { $0.value.day.path != path && $0.value.night.path != path }.mapValues { r in
            var r = r
            if r.dawn?.path == path { r.dawn = nil }
            if r.dusk?.path == path { r.dusk = nil }
            return r
        }
        save(); refresh()
    }

    /// Audio-reactive look options for whatever governs this display (its own assignment or the shared one).
    func reactive(for screen: NSScreen) -> ReactiveOptions { assignment(for: screen)?.reactive ?? ReactiveOptions() }
    func setReactive(_ o: ReactiveOptions, for screen: NSScreen) {
        let k = screen.stableKey
        let v: ReactiveOptions? = o.any ? o : nil
        if let (r, scope) = rule(for: screen) {
            state.dayNight?[scope] = r.mapAll { var a = $0; a.reactive = v; return a }
        } else if state.perScreen[k] != nil { state.perScreen[k]?.reactive = v }
        else if state.all != nil { state.all?.reactive = v }
        save(); refresh()
    }

    /// Per-wallpaper fit / focus / speed changed: update every assignment showing that item, in place (no reload).
    func updateOptions(itemID: String, _ o: WallpaperOptions?) {
        func fix(_ a: Assignment) -> Assignment { var a = a; if a.itemID == itemID { a.options = o }; return a }
        state.all = state.all.map(fix)
        state.perScreen = state.perScreen.mapValues(fix)
        state.dayNight = state.dayNight?.mapValues { $0.mapAll(fix) }
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
        case .image: return (a.reactive?.any ?? false) || rule(for: screen) != nil || playlistGoverns(screen)
        }
    }
    /// Scopes ("*" or display keys) with a playing playlist: their stills get a window too, so changes cross-fade.
    var crossfadeScopes: Set<String> = [] { didSet { if crossfadeScopes != oldValue { refresh() } } }
    private func playlistGoverns(_ screen: NSScreen) -> Bool {
        crossfadeScopes.contains(screen.stableKey) || (crossfadeScopes.contains(EngineState.allKey) && state.perScreen[screen.stableKey] == nil)
    }

    func refresh() {
        if parked { updatePlayback(); return }   // rebuilt by unpark() when playback resumes
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

    var pausePrefs: PausePrefs {
        PausePrefs(pauseOnBattery: Pref.pauseOnBattery, batteryBelowPercent: Pref.batteryBelowPercent, pauseLowPower: Pref.pauseLowPower,
                   thermalLimit: Pref.thermalLimit, cpuAbovePercent: Pref.cpuAbovePercent, pauseWhenCovered: Pref.pauseWhenCovered)
    }

    func updatePlayback() {
        power.userPaused = state.userPaused
        let kind = PausePolicy.reason(power, pausePrefs)
        pauseKind = kind
        pauseReason = kind.map { $0.label.prefix(1).uppercased() + $0.label.dropFirst() }
        if kind == nil {
            pausedSince = nil
            if parked { unpark(); return }
        } else if pausedSince == nil { pausedSince = now() }
        var needAudio = false
        var displays: [DisplayPlayback] = []
        for s in surfaces.values {
            let covered = Pref.pauseWhenCovered && !s.visible
            let run = kind == nil && !covered
            s.setRunning(run)
            displays.append(covered ? .covered : .playing)
            if run && (s.assignment.reactive?.any ?? false) { needAudio = true }
        }
        statusText = PlaybackStatus.text(global: kind, displays: displays)
        if kind == nil, displays.isEmpty, !currentAssignments.isEmpty { statusText = "Showing a still image" }
        if needAudio != audioNeeded {
            audioNeeded = needAudio
            if !needAudio { surfaces.values.forEach { $0.resetReactive() } }
            onAudioNeedChanged?(needAudio)
        }
        tick += 1
    }

    // MARK: Memory hygiene: release players after a long pause

    /// Closes every wallpaper window (and its player and decoded frames) while a global pause lasts long.
    /// The desktop picture (a still of each wallpaper) shows meanwhile. Covered displays are not parked:
    /// their window is needed to notice when they are uncovered.
    func checkIdleRelease() {
        guard !parked, !surfaces.isEmpty, IdleRelease.shouldRelease(pausedSince: pausedSince, now: now(), afterMinutes: Pref.releaseAfterMinutes) else { return }
        park()
    }
    func park() {
        for s in surfaces.values { s.close() }
        for s in fading { s.close() }
        surfaces = [:]; fading = []
        parked = true
        if audioNeeded { audioNeeded = false; onAudioNeedChanged?(false) }
        statusText = PlaybackStatus.text(global: pauseKind, displays: [])
        tick += 1
    }
    private func unpark() {
        parked = false
        refresh()
    }

    private static func thermal() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .serious
        }
    }

    private static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    /// Every 5 s while the CPU limit is on: whole-Mac CPU use, averaged over 30 s by the gate.
    private func sampleCPU() {
        if cpuGate.thresholdPercent != Pref.cpuAbovePercent { cpuGate = CPUGate(thresholdPercent: Pref.cpuAbovePercent, window: 6) }
        guard Pref.cpuAbovePercent > 0 else { lastTicks = nil; if power.cpuBusy { power.cpuBusy = false; updatePlayback() }; return }
        guard let t = Self.cpuTicks() else { return }
        defer { lastTicks = t }
        guard let prev = lastTicks, let busy = CPUTicks.busyFraction(from: prev, to: t) else { return }
        let b = cpuGate.feed(busy)
        if b != power.cpuBusy { power.cpuBusy = b; updatePlayback() }
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
        var pct: Int?
        if let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                      let cur = d[kIOPSCurrentCapacityKey] as? Int, let mx = d[kIOPSMaxCapacityKey] as? Int, mx > 0 else { continue }
                pct = Int((Double(cur) / Double(mx) * 100).rounded())
            }
        }
        if b != power.onBattery || pct != power.batteryPercent { power.onBattery = b; power.batteryPercent = pct; updatePlayback() }
    }

    /// Test hook for the headless dev check: pretend a power condition (never touches the real system).
    func simulate(_ change: (inout PowerSnapshot) -> Void) { change(&power); updatePlayback() }

    private func observe() {
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.power.locked = true; self?.updatePlayback() } })
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.power.locked = false; self?.updatePlayback() } })
        let wnc = NSWorkspace.shared.notificationCenter
        observers.append(wnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.power.asleep = true; self?.updatePlayback() } })
        observers.append(wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.power.asleep = false; self?.updatePlayback() } })
        observers.append(wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.power.asleep = false; self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.power.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled; self?.updatePlayback() } })
        observers.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.power.thermal = Self.thermal(); self?.updatePlayback() } })
        timers.append(Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkBattery(); self?.checkIdleRelease() } })
        timers.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleCPU() } })
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
                                "onBattery": power.onBattery, "batteryPercent": power.batteryPercent ?? NSNull(), "lowPower": power.lowPower,
                                "locked": power.locked, "thermal": power.thermal.rawValue, "cpuBusy": power.cpuBusy, "parked": parked,
                                "statusText": statusText, "phase": phase().rawValue, "part": part().rawValue,
                                "audioNeeded": audioNeeded, "fading": fading.count, "screens": screens]
        if let d = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: Paths.status) }
    }
}
