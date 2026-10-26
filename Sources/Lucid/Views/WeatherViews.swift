// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Weather wallpapers: the Settings section (opt-in, privacy note, attribution) and the per-condition picker sheet.
import SwiftUI

struct WeatherSettingsSection: View {
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var engine: LucidEngine
    @State private var on = Pref.weatherEnabled
    var body: some View {
        GroupBox("Weather wallpapers") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Change wallpaper with the weather (rain, snow, clear, cloudy)", isOn: $on)
                    .onChange(of: on) { _, v in Pref.weatherEnabled = v; weather.tick(); engine.weatherDidChange() }
                Text("Status: \(weather.statusText)").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Weather status: \(weather.statusText)")
                Text("Off by default. When on, and only once you pick a weather wallpaper in Displays, Lucid asks Open-Meteo for the current weather at most every 30 minutes. It sends only an approximate location (rounded to about 10 km, from your time zone, or from the location you already allowed for Day & Night), over HTTPS, with no account or ID. Offline? Your normal wallpaper simply stays.")
                    .font(.caption).foregroundStyle(.secondary)
                if let u = WeatherService.attributionURL {
                    Link("Weather data by Open-Meteo.com (CC BY 4.0) ↗", destination: u).font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }
}

struct WeatherSheet: View {
    let target: DNTarget
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: LucidEngine
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [WeatherCondition: String] = [:]

    private var choices: [WallItem] { store.library.filter(\.isLocalReady) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(title: "Weather · \(target.name)", subtitle: "Pick a wallpaper for the weather you care about. Others keep your normal wallpaper.")
            ForEach(WeatherCondition.allCases, id: \.self) { c in
                Picker(selection: Binding(get: { ids[c] ?? "" }, set: { ids[c] = $0 })) {
                    Text("None (normal wallpaper)").tag("")
                    ForEach(choices) { Text($0.title + ($0.kind == .image ? " · photo" : "")).tag($0.id) }
                } label: { Label(c.label, systemImage: c.symbol) }
                    .accessibilityLabel("Wallpaper when the weather is \(c.label)")
            }
            if !Pref.weatherEnabled { Label("Weather wallpapers are off in Settings; turn them on to start.", systemImage: "cloud.sun").font(.caption).foregroundStyle(.orange) }
            if choices.isEmpty { Text("Add wallpapers to your library first.").foregroundStyle(.orange) }
            HStack {
                Button("Remove Weather Wallpapers") { engine.setWeather(WeatherRule(map: [:]), screenKey: target.screenKey); dismiss() }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    var m: [WeatherCondition: Assignment] = [:]
                    for (c, id) in ids where !id.isEmpty {
                        if let it = choices.first(where: { $0.id == id }), let a = store.readyAssignment(for: it) { m[c] = a }
                    }
                    engine.setWeather(WeatherRule(map: m), screenKey: target.screenKey)
                    store.weather.tick()
                    dismiss()
                }.buttonStyle(.borderedProminent).tint(accent.opacity(0.85)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 540)
        .onAppear {
            if let r = engine.state.weather?[target.screenKey ?? EngineState.allKey] { ids = r.map.mapValues(\.itemID) }
        }
    }
}
