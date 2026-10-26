// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Global keyboard shortcuts, as pure data and rules: which key + modifiers, their menu-style label, Carbon flags,
// conflicts, and the saved settings. Registration itself (Carbon RegisterEventHotKey, which needs no Accessibility
// permission and never sees other keystrokes) lives in HotkeyCenter.swift.
import Foundation

enum HotkeyModifier: String, Codable, CaseIterable { case control, option, shift, command }

enum HotkeyKey: String, Codable, CaseIterable {
    case p, n, b, q, w, space, leftArrow, rightArrow, upArrow, downArrow, comma, period, leftBracket, rightBracket
    /// macOS virtual key codes (kVK_*, US layout positions).
    var keyCode: UInt32 {
        switch self {
        case .p: return 0x23
        case .n: return 0x2D
        case .b: return 0x0B
        case .q: return 0x0C
        case .w: return 0x0D
        case .space: return 0x31
        case .leftArrow: return 0x7B
        case .rightArrow: return 0x7C
        case .downArrow: return 0x7D
        case .upArrow: return 0x7E
        case .comma: return 0x2B
        case .period: return 0x2F
        case .leftBracket: return 0x21
        case .rightBracket: return 0x1E
        }
    }
    var label: String {
        switch self {
        case .space: return "Space"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .comma: return ","
        case .period: return "."
        case .leftBracket: return "["
        case .rightBracket: return "]"
        default: return rawValue.uppercased()
        }
    }
}

struct Hotkey: Codable, Equatable, Hashable {
    var key: HotkeyKey
    var modifiers: Set<HotkeyModifier>

    var label: String {
        let order: [(HotkeyModifier, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return order.filter { modifiers.contains($0.0) }.map(\.1).joined() + key.label
    }
    /// Carbon modifier flags (controlKey, optionKey, shiftKey, cmdKey from Events.h).
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= 0x0100 }
        if modifiers.contains(.shift) { m |= 0x0200 }
        if modifiers.contains(.option) { m |= 0x0800 }
        if modifiers.contains(.control) { m |= 0x1000 }
        return m
    }
}

enum HotkeyAction: String, Codable, CaseIterable {
    case pauseResume, next, previous
    var label: String {
        switch self {
        case .pauseResume: return "Pause / Resume"
        case .next: return "Next wallpaper"
        case .previous: return "Previous wallpaper"
        }
    }
}

struct HotkeyBindings: Codable, Equatable {
    var enabled = false
    private var map: [String: Hotkey] = [:]

    func binding(_ a: HotkeyAction) -> Hotkey? { map[a.rawValue] }
    mutating func set(_ a: HotkeyAction, _ k: Hotkey?) { map[a.rawValue] = k }

    static let defaults: HotkeyBindings = {
        var b = HotkeyBindings()
        let hyper: Set<HotkeyModifier> = [.control, .option, .command]
        b.set(.pauseResume, Hotkey(key: .p, modifiers: hyper))
        b.set(.next, Hotkey(key: .rightArrow, modifiers: hyper))
        b.set(.previous, Hotkey(key: .leftArrow, modifiers: hyper))
        return b
    }()
    /// Choices offered in Settings for each action.
    static let presets: [Hotkey] = {
        let hyper: Set<HotkeyModifier> = [.control, .option, .command], co: Set<HotkeyModifier> = [.control, .option]
        return [HotkeyKey.p, .rightArrow, .leftArrow, .space, .n, .b, .period, .comma, .rightBracket, .leftBracket].map { Hotkey(key: $0, modifiers: hyper) }
            + [HotkeyKey.p, .rightArrow, .leftArrow].map { Hotkey(key: $0, modifiers: co) }
    }()

    init() {}
    /// Lenient: a shortcut that doesn't decode is dropped on its own; unreadable data gives the defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? nil ?? false
        map = ((try? c.decodeIfPresent(LossyDictionary<Hotkey>.self, forKey: .map)) ?? nil)?.values ?? [:]
    }
    static func decode(_ d: Data?) -> HotkeyBindings { d.flatMap { try? JSONDecoder().decode(HotkeyBindings.self, from: $0) } ?? defaults }
    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
}

enum HotkeyRules {
    /// Well-known macOS shortcuts we refuse to take over.
    static let reserved: [Hotkey: String] = [
        Hotkey(key: .space, modifiers: [.command]): "Spotlight",
        Hotkey(key: .space, modifiers: [.control]): "Input sources",
        Hotkey(key: .space, modifiers: [.command, .option]): "Finder search",
        Hotkey(key: .q, modifiers: [.command]): "Quit",
        Hotkey(key: .w, modifiers: [.command]): "Close window",
        Hotkey(key: .q, modifiers: [.control, .command]): "Lock Screen",
        Hotkey(key: .leftArrow, modifiers: [.control]): "Spaces",
        Hotkey(key: .rightArrow, modifiers: [.control]): "Spaces",
        Hotkey(key: .upArrow, modifiers: [.control]): "Mission Control",
        Hotkey(key: .downArrow, modifiers: [.control]): "App windows",
    ]

    static func problem(_ k: Hotkey) -> String? {
        if k.modifiers.isDisjoint(with: [.command, .control, .option]) { return "Add ⌘, ⌃ or ⌥" }
        if let r = reserved[k] { return "Used by macOS (\(r))" }
        return nil
    }

    /// Action -> why it can't be used (duplicate of an earlier action, or a rule problem).
    static func conflicts(_ b: HotkeyBindings) -> [HotkeyAction: String] {
        var out: [HotkeyAction: String] = [:]
        var taken: [Hotkey: HotkeyAction] = [:]
        for a in HotkeyAction.allCases {
            guard let k = b.binding(a) else { continue }
            if let p = problem(k) { out[a] = p; continue }
            if let first = taken[k] { out[a] = "Same as \(first.label)"; continue }
            taken[k] = a
        }
        return out
    }

    /// What to register, in action order, skipping conflicts.
    static func toRegister(_ b: HotkeyBindings) -> [(HotkeyAction, Hotkey)] {
        let bad = conflicts(b)
        return HotkeyAction.allCases.compactMap { a in b.binding(a).flatMap { bad[a] == nil ? (a, $0) : nil } }
    }
}
