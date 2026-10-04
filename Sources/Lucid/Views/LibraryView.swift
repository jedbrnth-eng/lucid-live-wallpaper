// Downloaded, Favorites, Recents and playlist pages.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

enum LibMode { case downloaded, favorites, recents }
enum LibSort: String, CaseIterable { case added = "Recently Added", used = "Recently Used", name = "Name", size = "Largest" }

struct LibraryView: View {
    let mode: LibMode
    @EnvironmentObject var store: Store
    @State private var selected: WallItem?
    @State private var dropping = false
    @State private var kind = "All"
    @State private var q = ""
    @State private var sort: LibSort = .added

    private var base: [WallItem] {
        switch mode {
        case .downloaded: return store.library.filter(\.isLocalReady)
        case .favorites: return store.favorites.map { store.libraryItem($0.id) ?? $0 }
        case .recents: return Array(store.library.filter { $0.lastAppliedAt != nil && $0.isLocalReady }
                .sorted { ($0.lastAppliedAt ?? .distantPast) > ($1.lastAppliedAt ?? .distantPast) }.prefix(40))
        }
    }
    private var title: String { mode == .downloaded ? "Downloaded" : mode == .favorites ? "Favorites" : "Recently Used" }

    private func filtered() -> [WallItem] {
        var items = base.filter { it in
            let kindOK = kind == "All" || (kind == "Videos" ? it.kind == .video : kind == "Photos" ? it.kind == .image : it.source.label == kind)
            let qOK = q.isEmpty || it.title.localizedCaseInsensitiveContains(q) || (it.author ?? "").localizedCaseInsensitiveContains(q)
                || (it.tags ?? []).contains { $0.localizedCaseInsensitiveContains(q) }
            return kindOK && qOK
        }
        if mode != .recents {
            switch sort {
            case .added: items.sort { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
            case .used: items.sort { ($0.lastAppliedAt ?? .distantPast) > ($1.lastAppliedAt ?? .distantPast) }
            case .name: items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .size: items.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
            }
        }
        return items
    }

    var body: some View {
        let items = filtered()
        let sources = Array(Set(base.map(\.source.label))).sorted()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    Header(title: title, subtitle: subtitle(items.count))
                    Spacer()
                    if mode == .downloaded {
                        Button { pickFiles() } label: { Label("Import…", systemImage: "plus") }
                        Button { NSWorkspace.shared.open(Paths.media) } label: { Label("Folder", systemImage: "folder") }
                    }
                    if !items.isEmpty {
                        Button { if let r = items.randomElement() { store.setWallpaper(r) } } label: { Label("Shuffle", systemImage: "shuffle") }
                    }
                }
                HStack(spacing: 10) {
                    TextField("Search title, credit or tag", text: $q).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                    if mode != .recents {
                        Picker("Sort", selection: $sort) { ForEach(LibSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            .frame(maxWidth: 220)
                    }
                }
                Chips(options: ["All", "Videos", "Photos"] + sources, selected: kind) { kind = $0 }
                if items.isEmpty { emptyState }
                Grid(items: items, selected: $selected)
            }.padding(24)
        }
        .overlay { if dropping { RoundedRectangle(cornerRadius: 16).stroke(accent, style: StrokeStyle(lineWidth: 3, dash: [10])).padding(8) } }
        .sheet(item: $selected) { DetailView(item: $0) }
    }
    @ViewBuilder private var emptyState: some View {
        if mode == .downloaded && base.isEmpty { firstRunDropZone } else { plainEmptyState }
    }
    private var firstRunDropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 54)).foregroundStyle(accent)
            Text("Drop videos or photos here").font(.title.bold())
            Text("4K videos (MP4, MOV, WebM, MKV…) and photos. Drop a whole folder if you like.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { pickFiles() } label: { Label("Import…", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(accent)
                Button { NSWorkspace.shared.open(Paths.media) } label: { Label("Open Lucid folder", systemImage: "folder") }
            }
            Text("Or drop files straight into the Lucid folder and they appear here on their own.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 56)
        .background(RoundedRectangle(cornerRadius: 20).strokeBorder(accent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [10])))
        .padding(.top, 20)
    }
    private var plainEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: mode == .favorites ? "heart" : mode == .recents ? "clock" : "sparkles.tv").font(.system(size: 44)).foregroundStyle(accent)
            Text(base.isEmpty ? "Nothing here yet" : "No matches").font(.title3.bold())
            Text(emptyHint).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 80)
    }
    private func subtitle(_ n: Int) -> String {
        switch mode {
        case .downloaded: return "\(n) on this Mac · \(ByteCountFormatter.string(fromByteCount: store.libraryBytes, countStyle: .file)) · hover a card → Apply. Drop your own videos/photos here."
        case .favorites: return "\(n) favorite\(n == 1 ? "" : "s") · tap ♥ on any wallpaper to add it here"
        case .recents: return "The last wallpapers you put on the desktop — reapply one with a click"
        }
    }
    private var emptyHint: String {
        switch mode {
        case .downloaded: return "Pick something in Discover → Set as Wallpaper, or drop a video/photo here."
        case .favorites: return "Hover any wallpaper and tap ♥."
        case .recents: return "Wallpapers you apply show up here."
        }
    }
    private func pickFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.allowedContentTypes = [.movie, .video, .image, .folder]
        if p.runModal() == .OK { store.importFiles(p.urls) }
    }
}

struct PlaylistView: View {
    let id: String
    @EnvironmentObject var store: Store
    @State private var selected: WallItem?
    @State private var renaming = false
    @State private var name = ""
    @State private var confirmDelete = false
    var body: some View {
        if let pl = store.playlists.first(where: { $0.id == id }) {
            content(pl)
        } else {
            Text("Playlist not found").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func content(_ pl: Playlist) -> some View {
        let active = store.activePlaylistID == id
        let sub = "\(pl.items.count) wallpaper\(pl.items.count == 1 ? "" : "s") · rotates every \(Store.intervalLabel(pl.minutes))" + (pl.shuffle ? " · shuffled" : " · in order") + (active ? " · PLAYING" : "")
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Header(title: pl.name, subtitle: sub)
                controls(pl, active: active)
                if pl.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list").font(.system(size: 40)).foregroundStyle(accent)
                        Text("Empty playlist").font(.title3.bold())
                        Text("Right-click any wallpaper → Add to Playlist → \(pl.name).").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 60)
                }
                Grid(items: pl.items.map { store.libraryItem($0.id) ?? $0 }, selected: $selected, playlistID: id)
            }.padding(24)
        }
        .sheet(item: $selected) { DetailView(item: $0) }
        .alert("Rename Playlist", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Save") { var p = pl; p.name = name.ifEmpty(pl.name); store.updatePlaylist(p) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(pl.name)”? Wallpapers stay in your library.", isPresented: $confirmDelete) {
            Button("Delete Playlist", role: .destructive) { store.deletePlaylist(id) }
        }
    }
    private func controls(_ pl: Playlist, active: Bool) -> some View {
        HStack(spacing: 12) {
            Button { active ? store.stopPlaylist() : store.playPlaylist(id) } label: {
                Label(active ? "Stop Playlist" : "Play Playlist", systemImage: active ? "stop.fill" : "play.fill")
            }.buttonStyle(.borderedProminent).tint(active ? .orange : accent.opacity(0.85)).disabled(pl.items.isEmpty)
            if active { Button { store.next() } label: { Label("Next", systemImage: "forward.fill") } }
            Toggle("Shuffle", isOn: Binding(get: { pl.shuffle }, set: { var p = pl; p.shuffle = $0; store.updatePlaylist(p) })).toggleStyle(.switch)
            Picker("Change every", selection: Binding(get: { pl.minutes }, set: { var p = pl; p.minutes = $0; store.updatePlaylist(p) })) {
                ForEach([5, 15, 30, 60, 180, 360, 1440], id: \.self) { Text(Store.intervalLabel($0)).tag($0) }
            }.frame(maxWidth: 220)
            Spacer()
            Menu {
                Button("Rename…") { name = pl.name; renaming = true }
                Button("Delete Playlist", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }.fixedSize()
        }
    }
}
