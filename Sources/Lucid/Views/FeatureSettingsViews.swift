// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Settings sections and sheets for audio-reactive looks and Day/Night wallpapers.
import SwiftUI
import AppKit

private func timeText(_ d: Date?) -> String {
    guard let d else { return "—" }
    let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
    return f.string(from: d)
}

// MARK: - Settings

struct AudioSettingsSection: View {
    @EnvironmentObject var audio: AudioReactive
    @State private var on = Pref.audioReactive
    @State private var sensitivity = Pref.audioSensitivity
    var body: some View {
        GroupBox("Audio reactive") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Let wallpapers react to the music your Mac plays", isOn: $on)
                    .onChange(of: on) { _, v in Pref.audioReactive = v; audio.reevaluate() }
                HStack {
                    Text("Sensitivity")
                    Slider(value: $sensitivity, in: 0.25...4).frame(maxWidth: 220)
                        .onChange(of: sensitivity) { _, v in Pref.audioSensitivity = v }
                    Text(String(format: "%.1f×", sensitivity)).monospacedDigit().foregroundStyle(.secondary)
                }.disabled(!on)
                HStack(spacing: 8) {
                    Circle().fill(audio.status == .running ? accent : Color.secondary).frame(width: 8, height: 8)
                    Text(audio.status.text).font(.caption).foregroundStyle(audio.status == .running ? .primary : .secondary)
                    if audio.status == .running { ProgressView(value: Double(audio.level)).frame(width: 80).tint(accent) }
                }
                Text("Uses macOS system-audio capture (never the microphone); macOS asks once for permission. Capture runs only while an audio-reactive wallpaper is on screen and not paused, and stops completely otherwise. Pick looks per display in Displays: pulse on bass, glow with volume, spectrum bars. Needs macOS 14.2 or later.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }
}

struct DayNightSettingsSection: View {
    @EnvironmentObject var dayNight: DayNightController
    @State private var manual = Pref.dayNightManual
    @State private var useLocation = Pref.dayNightUseLocation
    @State private var dayStart = Pref.dayStartMinute
    @State private var nightStart = Pref.nightStartMinute

    private func minutesBinding(_ v: Binding<Int>, save: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(v.wrappedValue) * 60) },
                set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    v.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0); save(v.wrappedValue); dayNight.evaluate()
                })
    }

    var body: some View {
        GroupBox("Day & Night") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Switch at", selection: $manual) {
                    Text("Sunrise and sunset (automatic)").tag(false); Text("Fixed times").tag(true)
                }.pickerStyle(.radioGroup)
                    .onChange(of: manual) { _, v in Pref.dayNightManual = v; dayNight.evaluate() }
                if manual {
                    DatePicker("Day starts", selection: minutesBinding($dayStart) { Pref.dayStartMinute = $0 }, displayedComponents: .hourAndMinute)
                        .frame(maxWidth: 220)
                    DatePicker("Night starts", selection: minutesBinding($nightStart) { Pref.nightStartMinute = $0 }, displayedComponents: .hourAndMinute)
                        .frame(maxWidth: 220)
                } else {
                    Toggle("Use my location for more accurate times (otherwise your time zone's city is used)", isOn: $useLocation)
                        .onChange(of: useLocation) { _, v in Pref.dayNightUseLocation = v; if v { dayNight.requestLocation() }; dayNight.evaluate() }
                }
                let today = dayNight.todayTimes()
                Text(dayNight.sourceText + (today.map { " · today ☀︎ \(timeText($0.0)) ☾ \(timeText($0.1))" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text("Now: \(dayNight.part.rawValue.capitalized) · next sunrise/sunset switch \(timeText(dayNight.nextChange))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Set a Day/Night pair in Displays. It switches with a short cross-fade and re-checks after sleep, time zone or clock changes.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }
}

// MARK: - Day/Night picker

struct DNTarget: Identifiable {
    let screenKey: String?
    let name: String
    var id: String { screenKey ?? EngineState.allKey }
}

struct DayNightSheet: View {
    let target: DNTarget
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: LucidEngine
    @EnvironmentObject var dayNight: DayNightController
    @Environment(\.dismiss) private var dismiss
    @State private var dayID = ""
    @State private var nightID = ""
    @State private var dawnID = ""
    @State private var duskID = ""

    private var choices: [WallItem] {
        store.library.filter(\.isLocalReady)
    }
    private func label(_ it: WallItem) -> String {
        it.title + (it.kind == .image ? " · photo" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "Day/Night · \(target.name)", subtitle: "One wallpaper from sunrise to sunset, another at night, with a short cross-fade.")
            Picker("☀︎ Day", selection: $dayID) {
                Text("Choose…").tag("")
                ForEach(choices) { Text(label($0)).tag($0.id) }
            }
            Picker("☾ Night", selection: $nightID) {
                Text("Choose…").tag("")
                ForEach(choices) { Text(label($0)).tag($0.id) }
            }
            Picker("🌅 Dawn (optional)", selection: $dawnID) {
                Text("None (use Day/Night)").tag("")
                ForEach(choices) { Text(label($0)).tag($0.id) }
            }.accessibilityLabel("Optional dawn wallpaper")
            Picker("🌇 Dusk (optional)", selection: $duskID) {
                Text("None (use Day/Night)").tag("")
                ForEach(choices) { Text(label($0)).tag($0.id) }
            }.accessibilityLabel("Optional dusk wallpaper")
            Text("Dawn runs from first light until the sun is a little up; dusk from golden hour until last light (with fixed times: the first and last hour of the day).")
                .font(.caption).foregroundStyle(.secondary)
            if choices.isEmpty { Text("Add wallpapers to your library first.").foregroundStyle(.orange) }
            Text(dayNight.sourceText + (dayNight.todayTimes().map { " · today ☀︎ \(timeText($0.0)) ☾ \(timeText($0.1))" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Set Day/Night") {
                    if let d = choices.first(where: { $0.id == dayID }), let n = choices.first(where: { $0.id == nightID }) {
                        store.setDayNight(day: d, night: n, dawn: choices.first { $0.id == dawnID }, dusk: choices.first { $0.id == duskID },
                                          screenKey: target.screenKey)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent).tint(accent.opacity(0.85)).keyboardShortcut(.defaultAction)
                .disabled(dayID.isEmpty || nightID.isEmpty)
            }
        }
        .padding(20).frame(width: 540)
        .onAppear {
            let scope = target.screenKey ?? EngineState.allKey
            if let r = engine.state.dayNight?[scope] {
                dayID = r.day.itemID; nightID = r.night.itemID; dawnID = r.dawn?.itemID ?? ""; duskID = r.dusk?.itemID ?? ""
            }
        }
    }
}
