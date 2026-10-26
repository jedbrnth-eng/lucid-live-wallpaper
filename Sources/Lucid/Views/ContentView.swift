// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Main window: sidebar navigation and the now-playing bar.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// MARK: - Views

enum Nav: Hashable { case home, discover(Source), liveTheme(String), library(LibFilter), favorites, recents, playlist(String), displays, settings }

/// Highlight colours, the same cyan and pink as the website (see Theme).
let accent = Theme.cyan
let accent2 = Theme.pink

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: LucidEngine
    @State private var nav: Nav? = .home
    @State private var newPlaylist = false
    @State private var newName = ""
    @State private var droppingAny = false

    var body: some View {
        NavigationSplitView {
            List(selection: $nav) {
                Label("Home", systemImage: "house").tag(Nav.home)
                Section("Discover · 4K only") {
                    ForEach(Source.discoverable) { s in
                        Label(s.label, systemImage: s.icon).tag(Nav.discover(s))
                    }
                }
                Section("My Library") {
                    Label("Downloaded", systemImage: "square.grid.2x2").badge(store.library.filter(\.isLocalReady).count).tag(Nav.library(.all))
                    Label("Favorites", systemImage: "heart").badge(store.favorites.count).tag(Nav.favorites)
                    Label("Recently Used", systemImage: "clock.arrow.circlepath").tag(Nav.recents)
                }
                Section {
                    ForEach(store.playlists) { pl in
                        Label(pl.name, systemImage: store.isPlaying(pl.id) ? "play.circle.fill" : "music.note.list")
                            .badge(pl.items.count).tag(Nav.playlist(pl.id))
                    }
                    Button { newName = ""; newPlaylist = true } label: { Label("New Playlist…", systemImage: "plus") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                } header: { Text("Playlists") }
                Section("Playback") {
                    Label("Displays", systemImage: "display.2").tag(Nav.displays)
                    Label("Settings", systemImage: "gearshape").tag(Nav.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .alert("New Playlist", isPresented: $newPlaylist) {
                TextField("Name (e.g. Cozy Rain, Space Night)", text: $newName)
                Button("Create") { let p = store.createPlaylist(newName); nav = .playlist(p.id) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Group wallpapers and let them rotate on a timer.") }
            .safeAreaInset(edge: .bottom) { NowPlayingBar().padding(10) }
        } detail: {
            Group {
                switch nav ?? .home {
                case .home: AnyView(HomeView(go: { nav = $0 }))
                case .liveTheme(let t): AnyView(LiveView(initialTheme: t).id(t))
                case .discover(let s): s == .aerials ? AnyView(AerialsView()) : s == .live ? AnyView(LiveView()) : AnyView(DiscoverView(source: s).id(s))
                case .library: AnyView(LibraryView(mode: .downloaded))
                case .favorites: AnyView(LibraryView(mode: .favorites))
                case .recents: AnyView(LibraryView(mode: .recents))
                case .playlist(let id): AnyView(PlaylistView(id: id).id(id))
                case .displays: AnyView(DisplaysView())
                case .settings: AnyView(ScrollView { SettingsView().padding(24).frame(maxWidth: 640, alignment: .leading) })
                }
            }
            .overlay {
                if droppingAny {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.bg.opacity(0.75))
                        RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(accent, style: StrokeStyle(lineWidth: 3, dash: [12]))
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 46)).foregroundStyle(accent)
                            Text("Drop to add to your library").font(.title2.bold())
                            Text("Videos (MP4, MOV, WebM, MKV…) and photos · or drop a whole folder").foregroundStyle(.secondary)
                        }
                    }.padding(10).allowsHitTesting(false)
                }
            }
            .background(Theme.backdrop.ignoresSafeArea())
            .dropDestination(for: URL.self) { urls, _ in store.importFiles(urls); return !urls.isEmpty } isTargeted: { droppingAny = $0 }
            .overlay(alignment: .bottom) {
                if let t = store.toast {
                    Text(t).font(.callout.weight(.medium)).foregroundStyle(Theme.ink).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(Theme.line))
                        .shadow(color: Theme.violet.opacity(0.35), radius: 14)
                        .padding(.bottom, 18).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: store.toast)
        }
        .onAppear { PreviewCenter.shared.attach(engine) }
    }
}

struct NowPlayingBar: View {
    @EnvironmentObject var engine: LucidEngine
    @EnvironmentObject var store: Store
    var body: some View {
        let title = engine.currentAssignments.first?.title
        VStack(alignment: .leading, spacing: 6) {
            Text("NOW ON DESKTOP").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(title ?? "Nothing set yet").font(.callout.weight(.semibold)).lineLimit(1)
            if let p = store.activePlaylist {
                Text("▶︎ \(p.name) · every \(Store.intervalLabel(p.minutes))").font(.caption2).foregroundStyle(accent).lineLimit(1)
            }
            HStack(spacing: 8) {
                Button { store.previous() } label: { Image(systemName: "backward.fill") }.help("Previous wallpaper")
                Button { engine.togglePause() } label: { Image(systemName: engine.state.userPaused ? "play.fill" : "pause.fill") }
                    .help(engine.state.userPaused ? "Resume" : "Pause")
                Button { store.next() } label: { Image(systemName: "forward.fill") }
                    .help(store.activePlaylist.map { "Next in “\($0.name)”" } ?? "Random wallpaper from library")
                if let c = store.currentItem {
                    Button { store.toggleFavorite(c) } label: { Image(systemName: store.isFavorite(c.id) ? "heart.fill" : "heart") }
                        .foregroundStyle(store.isFavorite(c.id) ? accent2 : .primary).help("Favorite")
                }
                Spacer()
                if let r = engine.pauseReason { Text(r).font(.caption2).foregroundStyle(.orange).lineLimit(1) }
            }
            .buttonStyle(.borderless)
            .disabled(title == nil)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.line))
    }
}
