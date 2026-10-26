// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

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
            Rectangle().fill(LinearGradient(colors: [Theme.violet.opacity(0.10), Theme.bg2.opacity(0.6)], startPoint: .top, endPoint: .bottom))
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
    /// Opens the detail sheet (click, Return/Space when focused, VoiceOver default action).
    var onOpen: (() -> Void)? = nil
    @EnvironmentObject var store: Store
    @EnvironmentObject var dl: Downloader
    @EnvironmentObject var engine: LucidEngine
    @State private var hover = false
    @FocusState private var focused: Bool
    var body: some View {
        let current = engine.currentAssignments.contains { $0.itemID == item.id }
        let local = store.libraryItem(item.id) ?? item
        let onMac = store.inLibrary(item.id) || (item.localPath.map { FileManager.default.fileExists(atPath: $0) } ?? false)
        let lit = hover || focused
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                .overlay(RemoteImage(url: item.thumbURL, localPath: local.thumbPath ?? item.thumbPath))
                .overlay(PreviewLayer(item: local, wanted: lit))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(current ? accent : (lit ? Theme.muted.opacity(0.7) : Theme.line), lineWidth: current || focused ? 2 : 1))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        Badge(text: item.resLabel, color: item.is4K ? accent : .orange)
                        if item.kind == .video { Badge(text: "LIVE", color: accent2) }
                    }.padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if current { Image(systemName: "checkmark.seal.fill").foregroundStyle(accent).padding(8) }
                    else if store.isFavorite(item.id) && !lit { Image(systemName: "heart.fill").foregroundStyle(accent2).padding(8) }
                    else if onMac {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.white.opacity(0.85)).padding(8).help("On this Mac")
                    }
                }
                .overlay(alignment: .bottom) {
                    if let p = dl.progress[item.id] {
                        ProgressView(value: p).tint(accent).padding(8).background(.black.opacity(0.4))
                    } else if lit {
                        HStack(spacing: 6) {
                            Button { store.toggleFavorite(item) } label: {
                                Image(systemName: store.isFavorite(item.id) ? "heart.fill" : "heart")
                                    .foregroundStyle(store.isFavorite(item.id) ? accent2 : .white)
                            }.help("Favorite")
                            Spacer()
                            Button { store.setWallpaper(item) } label: {
                                Label(current ? "On Desktop" : onMac ? "Apply" : "Download & Apply", systemImage: current ? "checkmark" : "sparkles.tv")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(Theme.ink)).foregroundStyle(Theme.bg)
                            }.help(onMac ? "Set as wallpaper on all displays" : "Download in full quality (can be hundreds of MB), then set on all displays")
                        }
                        .buttonStyle(.plain).padding(.horizontal, 10).padding(.vertical, 8)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .transition(.opacity)
                    }
                }
                .shadow(color: lit ? Theme.violet.opacity(0.35) : .clear, radius: 16, y: 6)
                .scaleEffect(lit ? 1.02 : 1)
                .animation(.easeOut(duration: 0.18), value: lit)
            Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            Text([item.author, item.category].compactMap { $0 }.joined(separator: " · ").ifEmpty(item.source.label))
                .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .focusable(onOpen != nil)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.return) { open() }
        .onKeyPress(.space) { open() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(current: current, onMac: onMac))
        .accessibilityHint("Opens details")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { _ = open() }
        .accessibilityAction(named: current ? "On desktop" : onMac ? "Apply" : "Download and apply") { store.setWallpaper(item) }
        .accessibilityAction(named: store.isFavorite(item.id) ? "Remove from favorites" : "Add to favorites") { store.toggleFavorite(item) }
    }
    private func open() -> KeyPress.Result {
        guard let onOpen else { return .ignored }
        onOpen(); return .handled
    }
    private func accessibilityText(current: Bool, onMac: Bool) -> String {
        var parts = [item.title]
        if let c = item.category ?? item.author { parts.append(c) }
        parts.append("\(item.resLabel) \(item.kind == .video ? "live video" : "photo")")
        if current { parts.append("on your desktop now") } else if onMac { parts.append("on this Mac") }
        if store.isFavorite(item.id) { parts.append("favorite") }
        return parts.joined(separator: ", ")
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
                Card(item: item, onOpen: { selected = item })
                    .onTapGesture { selected = item }
                    .contextMenu { ItemMenu(item: item, playlistID: playlistID) }
            }
        }
    }
}

struct Header: View {
    let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 30, weight: .bold)).tracking(-0.6).foregroundStyle(Theme.ink)
            Text(subtitle).font(.callout).foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
                        .foregroundStyle(o == selected ? Theme.ink : Theme.muted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(o == selected ? Theme.violet.opacity(0.28) : Theme.surface))
                        .overlay(Capsule().stroke(o == selected ? Theme.violet.opacity(0.9) : Theme.line))
                        .accessibilityAddTraits(o == selected ? .isSelected : [])
                }
            }
        }
    }
}
