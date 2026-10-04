// Reusable views: cards, grids, badges, headers and remote images.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// Image loading with UA header + memory cache
final class ImageCache { static let shared: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 600; return c }() }

struct RemoteImage: View {
    let url: String?
    var localPath: String? = nil
    @State private var img: NSImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            Rectangle().fill(LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            if let img { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) }
            else if failed { Image(systemName: "photo").foregroundStyle(.tertiary) }
            else { ProgressView().controlSize(.small) }
        }
        .task(id: (localPath ?? "") + (url ?? "")) { await load() }
    }
    private func load() async {
        let key = (localPath ?? url ?? "") as NSString
        if let c = ImageCache.shared.object(forKey: key) { img = c; return }
        if let p = localPath, FileManager.default.fileExists(atPath: p) {
            if let i = NSImage(contentsOfFile: p) { ImageCache.shared.setObject(i, forKey: key); img = i; return }
        }
        guard let s = url, let u = URL(string: s) else { failed = true; return }
        do {
            let (d, _) = try await Net.session.data(from: u)
            if let i = NSImage(data: d) { ImageCache.shared.setObject(i, forKey: key); img = i } else { failed = true }
        } catch { failed = true }
    }
}

struct Badge: View {
    let text: String; var color: Color = accent
    var body: some View {
        Text(text).font(.caption2.weight(.heavy)).padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.65))).overlay(Capsule().stroke(color.opacity(0.8), lineWidth: 1))
            .foregroundStyle(color)
    }
}

struct Card: View {
    let item: WallItem
    @EnvironmentObject var store: Store
    @EnvironmentObject var dl: Downloader
    @EnvironmentObject var engine: WallpaperEngine
    @State private var hover = false
    var body: some View {
        let current = engine.state.all?.itemID == item.id || engine.state.perScreen.values.contains { $0.itemID == item.id }
        VStack(alignment: .leading, spacing: 6) {
            Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                .overlay(RemoteImage(url: item.thumbURL, localPath: item.thumbPath))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(current ? accent : (hover ? accent.opacity(0.5) : Color.white.opacity(0.08)), lineWidth: current ? 2 : 1))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        Badge(text: item.resLabel, color: item.is4K ? accent : .orange)
                        if item.kind == .video { Badge(text: "LIVE", color: accent2) }
                    }.padding(7)
                }
                .overlay(alignment: .topTrailing) {
                    if current { Image(systemName: "checkmark.seal.fill").foregroundStyle(accent).padding(7) }
                    else if store.isFavorite(item.id) && !hover { Image(systemName: "heart.fill").foregroundStyle(accent2).padding(7) }
                    else if store.inLibrary(item.id) || (item.source == .aerials && item.localPath != nil) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.white.opacity(0.85)).padding(7).help("On this Mac")
                    }
                }
                .overlay(alignment: .bottom) {
                    if let p = dl.progress[item.id] {
                        ProgressView(value: p).tint(accent).padding(8).background(.black.opacity(0.4))
                    } else if hover {
                        HStack(spacing: 6) {
                            Button { store.toggleFavorite(item) } label: {
                                Image(systemName: store.isFavorite(item.id) ? "heart.fill" : "heart")
                                    .foregroundStyle(store.isFavorite(item.id) ? accent2 : .white)
                            }.help("Favorite")
                            Spacer()
                            Button { store.setWallpaper(item) } label: {
                                Label(current ? "On Desktop" : "Apply", systemImage: current ? "checkmark" : "sparkles.tv").font(.caption.weight(.bold))
                            }.help("Set as wallpaper on all displays")
                        }
                        .buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 7)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .scaleEffect(hover ? 1.015 : 1).animation(.easeOut(duration: 0.15), value: hover)
            Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
            Text([item.author, item.category].compactMap { $0 }.joined(separator: " · ").ifEmpty(item.source.label))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

extension String { func ifEmpty(_ s: String) -> String { isEmpty ? s : self } }

struct ItemMenu: View {
    let item: WallItem
    var playlistID: String? = nil
    @EnvironmentObject var store: Store
    var body: some View {
        Button("Set as Wallpaper (All Displays)") { store.setWallpaper(item) }
        if NSScreen.screens.count > 1 {
            ForEach(NSScreen.screens, id: \.stableKey) { s in
                Button("Set on \(s.localizedName)") { store.setWallpaper(item, screenKey: s.stableKey) }
            }
        }
        Divider()
        Button(store.isFavorite(item.id) ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(item) }
        Menu("Add to Playlist") {
            ForEach(store.playlists) { pl in Button(pl.name) { store.addToPlaylist(item, pl.id) } }
            if !store.playlists.isEmpty { Divider() }
            Button("New Playlist with This") { store.createPlaylist("", with: item) }
        }
        if let pid = playlistID { Button("Remove from This Playlist") { store.removeFromPlaylist(item.id, pid) } }
        Divider()
        if let lib = store.libraryItem(item.id) {
            if let p = lib.localPath { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) } }
            Button("Remove from Library", role: .destructive) { store.remove(lib) }
        } else {
            Button("Download to Library") { store.download(item) }
        }
        if let p = item.pageURL, let u = URL(string: p) { Button("Open Source Page") { NSWorkspace.shared.open(u) } }
    }
}

struct Grid: View {
    let items: [WallItem]
    @Binding var selected: WallItem?
    var playlistID: String? = nil
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 420), spacing: 18)], spacing: 20) {
            ForEach(items) { item in
                Card(item: item)
                    .onTapGesture { selected = item }
                    .contextMenu { ItemMenu(item: item, playlistID: playlistID) }
            }
        }
    }
}

struct Header: View {
    let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct Chips: View {
    let options: [String]; let selected: String; let onPick: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { o in
                    Button(o) { onPick(o) }
                        .buttonStyle(.plain).font(.callout.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(o == selected ? accent.opacity(0.22) : Color.white.opacity(0.06)))
                        .overlay(Capsule().stroke(o == selected ? accent : Color.clear))
                }
            }
        }
    }
}
