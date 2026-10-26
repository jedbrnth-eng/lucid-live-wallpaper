// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Per-display wallpaper assignments.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

struct DisplaysView: View {
    @EnvironmentObject var engine: LucidEngine
    @EnvironmentObject var store: Store
    @EnvironmentObject var audio: AudioReactive
    @EnvironmentObject var dayNight: DayNightController
    @State private var dnTarget: DNTarget?
    @State private var weatherTarget: DNTarget?

    private func reactiveToggle(_ title: String, _ kp: WritableKeyPath<ReactiveOptions, Bool>, _ s: NSScreen) -> some View {
        Toggle(title, isOn: Binding(get: { engine.reactive(for: s)[keyPath: kp] },
                                    set: { var o = engine.reactive(for: s); o[keyPath: kp] = $0; engine.setReactive(o, for: s) }))
    }
    private func shortTime(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f.string(from: d)
    }
    private func weatherLine(_ w: WeatherRule) -> String {
        var parts: [String] = []
        for c in WeatherCondition.allCases {
            if let item = w.map[c] { parts.append("\(c.label) → \(item.title)") }
        }
        let now: String
        if let cur = engine.weatherNow() { now = " · now \(cur.label)" } else { now = " · no reading" }
        return "Weather: " + parts.joined(separator: " · ") + now
    }
    private func dayNightLine(_ r: DayNightRule, _ scope: String) -> String {
        var t = "Day/Night"
        if scope == EngineState.allKey { t += " (all displays)" }
        t += ": ☀︎ \(r.day.title) · ☾ \(r.night.title)"
        if let d = r.dawn { t += " · dawn \(d.title)" }
        if let d = r.dusk { t += " · dusk \(d.title)" }
        t += " · now \(dayNight.part.rawValue) · switches \(shortTime(dayNight.nextChange))"
        return t
    }
    @ViewBuilder private func screenRow(_ s: NSScreen) -> some View {
                    let a = engine.assignment(for: s)
                    let lib = a.flatMap { store.libraryItem($0.itemID) }
                    HStack(spacing: 16) {
                        Color.clear.frame(width: 220, height: 124)
                            .overlay(RemoteImage(url: lib?.thumbURL, localPath: lib?.thumbPath))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.localizedName).font(.headline)
                            Text("\(s.pixelSize) · \(s == NSScreen.main ? "main display" : "secondary")").font(.caption).foregroundStyle(.secondary)
                            Text(a?.title ?? "No wallpaper from this app").font(.callout.weight(.medium))
                            if let a {
                                let paused = engine.screenPaused(s)
                                Label(a.kind == .image ? "Still image" : (paused.map { "Paused — \($0)" } ?? "Playing live"),
                                      systemImage: a.kind == .image ? "photo" : (paused == nil ? "play.circle.fill" : "pause.circle"))
                                    .foregroundStyle(a.kind == .image ? Color.secondary : (paused == nil ? accent : .orange)).font(.caption)
                                if let w = engine.weatherRule(for: s) {
                                    Text(weatherLine(w))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                if let (r, scope) = engine.rule(for: s) {
                                    Text(dayNightLine(r, scope))
                                        .font(.caption2).foregroundStyle(.secondary)
                                } else {
                                    Text(engine.state.perScreen[s.stableKey] != nil ? "Set for this display only" : "Following “All Displays”")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer()
                        if a != nil {
                            Menu {
                                reactiveToggle("Pulse on bass", \.pulse, s)
                                reactiveToggle("Glow with volume", \.glow, s)
                                reactiveToggle("Spectrum bars", \.bars, s)
                            } label: { Label("Audio", systemImage: engine.reactive(for: s).any ? "waveform.circle.fill" : "waveform") }
                                .fixedSize().help("Audio-reactive looks for this wallpaper (turn on Audio reactive in Settings)")
                        }
                        Button("Day/Night…") { dnTarget = DNTarget(screenKey: s.stableKey, name: s.localizedName) }
                        if a != nil { Button("Clear") { engine.clear(screenKey: s.stableKey) } }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: "Displays", subtitle: "Each display gets its own looping player. New monitors follow the “All Displays” wallpaper automatically.")
                HStack {
                    Button { engine.togglePause() } label: {
                        Label(engine.state.userPaused ? "Resume All" : "Pause All", systemImage: engine.state.userPaused ? "play.fill" : "pause.fill")
                    }
                    Button { store.next() } label: { Label("Random from Library", systemImage: "shuffle") }
                    Button { dnTarget = DNTarget(screenKey: nil, name: "All Displays") } label: { Label("Day/Night for All…", systemImage: "sun.and.horizon") }
                    Button { weatherTarget = DNTarget(screenKey: nil, name: "All Displays") } label: { Label("Weather…", systemImage: "cloud.sun.rain") }
                        .help("Show a different wallpaper when it rains, snows, is clear or cloudy")
                    if let r = engine.pauseReason { Text("Paused: \(r)").foregroundStyle(.orange) }
                }
                if !Pref.audioReactive && engine.currentAssignments.contains(where: { $0.reactive?.any ?? false }) {
                    Label("Audio reactive is off in Settings, so the looks below are idle.", systemImage: "waveform.slash").font(.caption).foregroundStyle(.orange)
                }
                let _ = engine.tick
                ForEach(NSScreen.screens, id: \.stableKey) { s in screenRow(s) }
            }.padding(24)
        }
        .sheet(item: $dnTarget) { DayNightSheet(target: $0) }
        .sheet(item: $weatherTarget) { WeatherSheet(target: $0) }
    }
}
