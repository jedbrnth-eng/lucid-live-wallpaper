// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Settings section for global keyboard shortcuts.
import SwiftUI

struct HotkeySettingsSection: View {
    @EnvironmentObject var hotkeys: HotkeyCenter

    private func binding(_ a: HotkeyAction) -> Binding<String> {
        Binding(get: { hotkeys.bindings.binding(a).map { HotkeyBindings.presets.firstIndex(of: $0).map(String.init) ?? "" } ?? "none" },
                set: { v in
                    var b = hotkeys.bindings
                    b.set(a, Int(v).flatMap { HotkeyBindings.presets.indices.contains($0) ? HotkeyBindings.presets[$0] : nil })
                    hotkeys.update(b)
                })
    }

    var body: some View {
        GroupBox("Keyboard shortcuts") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use global shortcuts (work in any app)", isOn: Binding(get: { hotkeys.bindings.enabled },
                                                                                set: { var b = hotkeys.bindings; b.enabled = $0; hotkeys.update(b) }))
                ForEach(HotkeyAction.allCases, id: \.self) { a in
                    HStack {
                        Picker(a.label, selection: binding(a)) {
                            Text("None").tag("none")
                            ForEach(HotkeyBindings.presets.indices, id: \.self) { i in Text(HotkeyBindings.presets[i].label).tag(String(i)) }
                        }.frame(maxWidth: 300).accessibilityLabel("Shortcut for \(a.label)")
                        if let p = hotkeys.problems[a] {
                            Label(p, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        }
                    }.disabled(!hotkeys.bindings.enabled)
                }
                Text("Off by default. Lucid registers only these exact key combinations with macOS, so it needs no Accessibility or Input Monitoring permission and never sees anything else you type. A shortcut another app already uses is skipped and marked.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }
}
