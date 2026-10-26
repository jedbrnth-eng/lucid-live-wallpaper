// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Global shortcuts: labels, Carbon modifier flags, conflicts between Lucid's own shortcuts and well-known system ones,
// and saved settings that never crash on bad data.
import Foundation

func registerHotkeyTests() {
    let pause = Hotkey(key: .p, modifiers: [.control, .option, .command])
    let next = Hotkey(key: .rightArrow, modifiers: [.control, .option, .command])

    test("Hotkeys: labels read like macOS menus (⌃⌥⇧⌘ order)") {
        expectEqual(pause.label, "⌃⌥⌘P")
        expectEqual(next.label, "⌃⌥⌘→")
        expectEqual(Hotkey(key: .space, modifiers: [.command, .shift, .control]).label, "⌃⇧⌘Space")
    }
    test("Hotkeys: Carbon modifier flags and key codes") {
        expectEqual(pause.carbonModifiers, 0x1000 | 0x0800 | 0x0100)
        expectEqual(Hotkey(key: .n, modifiers: [.shift, .command]).carbonModifiers, 0x0200 | 0x0100)
        expectEqual(HotkeyKey.p.keyCode, 0x23)
        expectEqual(HotkeyKey.leftArrow.keyCode, 0x7B)
    }
    test("Hotkeys: shortcuts need ⌘, ⌃ or ⌥ and must not shadow well-known system shortcuts") {
        expectEqual(HotkeyRules.problem(Hotkey(key: .p, modifiers: [])), "Add ⌘, ⌃ or ⌥")
        expectEqual(HotkeyRules.problem(Hotkey(key: .p, modifiers: [.shift])), "Add ⌘, ⌃ or ⌥")
        expectEqual(HotkeyRules.problem(Hotkey(key: .space, modifiers: [.command])), "Used by macOS (Spotlight)")
        expectEqual(HotkeyRules.problem(Hotkey(key: .q, modifiers: [.command])), "Used by macOS (Quit)")
        expectEqual(HotkeyRules.problem(pause), nil)
    }
    test("Hotkeys: the same shortcut on two actions is a conflict; only the first keeps it") {
        var b = HotkeyBindings()
        b.set(.pauseResume, pause)
        b.set(.next, pause)
        let c = HotkeyRules.conflicts(b)
        expectEqual(c[.next], "Same as Pause / Resume")
        expectEqual(c[.pauseResume], nil)
        expectEqual(HotkeyRules.toRegister(b).map(\.0), [.pauseResume], "the duplicate isn't registered")
        b.set(.next, next)
        expect(HotkeyRules.conflicts(b).isEmpty)
        expectEqual(HotkeyRules.toRegister(b).map(\.0), [.pauseResume, .next])
    }
    test("Hotkeys: off by default; defaults are conflict-free; saved settings round-trip; junk decodes to defaults") {
        let d = HotkeyBindings.defaults
        expect(!d.enabled, "global shortcuts are opt-in")
        expect(HotkeyRules.conflicts(d).isEmpty)
        for a in HotkeyAction.allCases { if let k = d.binding(a) { expectEqual(HotkeyRules.problem(k), nil, "\(a)") } }
        var b = d; b.enabled = true; b.set(.previous, nil)
        expectEqual(HotkeyBindings.decode(b.encoded()), b)
        expectEqual(HotkeyBindings.decode(Data("{\"enabled\":true,\"map\":{\"next\":{\"key\":\"nope\",\"modifiers\":[]}}}".utf8)).binding(.next), nil,
                    "an unknown key drops just that shortcut")
        expectEqual(HotkeyBindings.decode(Data("💥".utf8)), HotkeyBindings.defaults)
        expectEqual(HotkeyBindings.decode(nil), HotkeyBindings.defaults)
    }
}
