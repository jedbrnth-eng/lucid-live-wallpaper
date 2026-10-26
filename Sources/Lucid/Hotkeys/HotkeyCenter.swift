// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Registers Lucid's global shortcuts with Carbon's RegisterEventHotKey. This public API delivers only the exact
// combinations registered, needs no Accessibility or Input Monitoring permission, and never sees other keystrokes.
// Off until the user turns it on in Settings. A combination another app already owns is reported, not stolen.
import AppKit
import Carbon

@MainActor final class HotkeyCenter: ObservableObject {
    static let shared = HotkeyCenter()
    private static let defaultsKey = "hotkeys"
    @Published private(set) var bindings: HotkeyBindings
    /// Action -> problem (duplicate, reserved by macOS, or taken by another app).
    @Published private(set) var problems: [HotkeyAction: String] = [:]
    var handler: ((HotkeyAction) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x4C55_4344   // 'LUCD'

    private init() {
        bindings = HotkeyBindings.decode(Pref.d.data(forKey: Self.defaultsKey))
    }

    func update(_ b: HotkeyBindings) {
        bindings = b
        Pref.d.set(b.encoded(), forKey: Self.defaultsKey)
        apply()
    }

    func apply() {
        unregisterAll()
        problems = bindings.enabled ? HotkeyRules.conflicts(bindings) : [:]
        guard bindings.enabled else { return }
        installHandlerIfNeeded()
        for (action, key) in HotkeyRules.toRegister(bindings) {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(HotkeyAction.allCases.firstIndex(of: action) ?? 0) + 1)
            let st = RegisterEventHotKey(key.key.keyCode, key.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
            if st == noErr, let ref { refs.append(ref) }
            else { problems[action] = st == eventHotKeyExistsErr ? "Already used by another app" : "Couldn't register (error \(st))" }
        }
    }

    var registeredCount: Int { refs.count }
    /// Dev check only: is this exact combination free right now? (registers and immediately unregisters)
    static func probe(_ k: Hotkey) -> OSStatus {
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(k.key.keyCode, k.carbonModifiers, EventHotKeyID(signature: signature, id: 99), GetApplicationEventTarget(), 0, &ref)
        if let ref { UnregisterEventHotKey(ref) }
        return st
    }

    private func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            let st = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard st == noErr, hk.signature == HotkeyCenter.signature, hk.id >= 1, Int(hk.id) <= HotkeyAction.allCases.count else { return OSStatus(eventNotHandledErr) }
            let action = HotkeyAction.allCases[Int(hk.id) - 1]
            DispatchQueue.main.async { MainActor.assumeIsolated { HotkeyCenter.shared.handler?(action) } }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
