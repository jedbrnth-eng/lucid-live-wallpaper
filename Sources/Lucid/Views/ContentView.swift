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

enum Nav: Hashable { case discover(Source), library(LibFilter), favorites, recents, playlist(String), displays, settings }

let accent = Color(red: 0.0, green: 0.94, blue: 1.0)
let accent2 = Color(red: 1.0, green: 0.17, blue: 0.84)

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: WallpaperEngine
    @State private var nav: Nav? = .discover(.aerials)
    @State private var newPlaylist = false
    @State private var newName = ""
    @State private var droppingAny = false

    var body: some View {
        NavigationSplitView {
            List(selection: $nav) {
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
                        Label(pl.name, systemImage: store.activePlaylistID == pl.id ? "play.circle.fill" : "music.note.list")
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
                switch nav ?? .discover(.aerials) {
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
                        RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.55))
                        RoundedRectangle(cornerRadius: 18).stroke(accent, style: StrokeStyle(lineWidth: 3, dash: [12]))
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 46)).foregroundStyle(accent)
                            Text("Drop to add to your library").font(.title2.bold())
                            Text("Videos (MP4, MOV, WebM, MKV…) and photos · or drop a whole folder").foregroundStyle(.secondary)
                        }
                    }.padding(10).allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in store.importFiles(urls); return !urls.isEmpty } isTargeted: { droppingAny = $0 }
            .overlay(alignment: .bottom) {
                if let t = store.toast {
                    Text(t).font(.callout.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(accent.opacity(0.5)))
                        .padding(.bottom, 18).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: store.toast)
        }
    }
}

struct NowPlayingBar: View {
    @EnvironmentObject var engine: WallpaperEngine
    @EnvironmentObject var store: Store
    var body: some View {
        let title = engine.state.all?.title ?? engine.state.perScreen.values.first?.title
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}
