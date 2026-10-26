// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Menu bar menu.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

struct MenuContent: View {
    @EnvironmentObject var engine: LucidEngine
    @EnvironmentObject var store: Store
    @EnvironmentObject var hotkeys: HotkeyCenter
    private func hint(_ a: HotkeyAction) -> String {
        guard hotkeys.bindings.enabled, hotkeys.problems[a] == nil, let k = hotkeys.bindings.binding(a) else { return "" }
        return "    " + k.label
    }
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(engine.currentAssignments.first?.title ?? "No wallpaper set")
        Text(engine.statusText)
        Divider()
        if let p = store.activePlaylist { Text("Playlist: \(p.name)") }
        Divider()
        Button((engine.state.userPaused ? "Resume" : "Pause") + hint(.pauseResume)) { engine.togglePause() }
        Button("Next Wallpaper" + hint(.next)) { store.next() }
        Button("Previous Wallpaper" + hint(.previous)) { store.previous() }
        if let c = store.currentItem {
            Button(store.isFavorite(c.id) ? "Unfavorite Current" : "♥ Favorite Current") { store.toggleFavorite(c) }
        }
        if !store.favorites.isEmpty {
            Menu("Favorites") {
                ForEach(store.favorites.prefix(15)) { f in Button(f.title) { store.setWallpaper(store.libraryItem(f.id) ?? f) } }
            }
        }
        let recent = store.library.filter { $0.lastAppliedAt != nil && $0.isLocalReady }
            .sorted { $0.lastAppliedAt! > $1.lastAppliedAt! }.prefix(10)
        if !recent.isEmpty {
            Menu("Recently Used") {
                ForEach(Array(recent)) { r in Button(r.title) { store.setWallpaper(r) } }
            }
        }
        if !store.playlists.isEmpty {
            Menu("Play Playlist") {
                ForEach(store.playlists) { p in Button(p.name) { store.playPlaylist(p.id) } }
                if store.activePlaylist != nil { Divider(); Button("Stop Playlist") { store.stopPlaylist() } }
            }
        }
        Divider()
        Button("Open Lucid…") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Quit Lucid") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
