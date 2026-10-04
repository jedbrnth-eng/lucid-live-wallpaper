// Wallpaper detail sheet with preview and apply options.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

final class PreviewPlayer: ObservableObject {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    func start(_ url: URL) {
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
    }
    func stop() { player.pause(); looper?.disableLooping(); looper = nil; player.removeAllItems() }
}

struct DetailView: View {
    let item: WallItem
    @EnvironmentObject var store: Store
    @EnvironmentObject var dl: Downloader
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = PreviewPlayer()
    @State private var started = false

    var body: some View {
        let lib = store.libraryItem(item.id)
        let it = lib ?? item
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                if it.kind == .video && started {
                    VideoPlayer(player: preview.player).disabled(true)
                } else {
                    RemoteImage(url: it.previewURL.flatMap { it.kind == .image ? $0 : nil } ?? it.thumbURL, localPath: it.kind == .image ? it.localPath : it.thumbPath)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.3)))

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(it.title).font(.title2.bold()).lineLimit(2)
                    Text([it.author, it.category, it.source.label].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                    if let t = it.tags, !t.isEmpty { Text(t.map { "#\($0)" }.joined(separator: " ")).font(.caption).foregroundStyle(accent.opacity(0.8)) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Badge(text: it.resLabel, color: it.is4K ? accent : .orange)
                        if it.kind == .video { Badge(text: "LIVE", color: accent2) }
                    }
                    Text(mediaDescription(it))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if !it.is4K { Text("Below 4K").font(.caption.bold()).foregroundStyle(.orange) }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield").foregroundStyle(.secondary)
                Text("License: \(it.license ?? "—")").font(.callout).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if let u = it.termsURL.flatMap(URL.init(string:)) ?? it.source.licenseURL { Link("terms ↗", destination: u).font(.callout) }
            }
            if let p = dl.progress[item.id] {
                HStack {
                    ProgressView(value: p).tint(accent)
                    Text("\(Int(p * 100))%").font(.caption.monospacedDigit())
                    Button("Cancel") { dl.cancel(item.id) }.buttonStyle(.borderless)
                }
            }
            if let e = dl.errors[item.id] { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            HStack(spacing: 10) {
                Button { store.setWallpaper(it) } label: { Label("Set as Wallpaper", systemImage: "sparkles.tv") }
                    .buttonStyle(.borderedProminent).tint(accent.opacity(0.85)).keyboardShortcut(.defaultAction)
                    .disabled(dl.progress[item.id] != nil)
                if NSScreen.screens.count > 1 {
                    Menu("Set on Display") {
                        ForEach(NSScreen.screens, id: \.stableKey) { s in
                            Button(s.localizedName) { store.setWallpaper(it, screenKey: s.stableKey) }
                        }
                    }.fixedSize()
                }
                if lib == nil && !(it.source == .aerials && it.localPath != nil) {
                    Button("Download") { store.download(it) }.disabled(dl.progress[item.id] != nil)
                }
                Button { store.toggleFavorite(it) } label: {
                    Image(systemName: store.isFavorite(it.id) ? "heart.fill" : "heart").foregroundStyle(store.isFavorite(it.id) ? accent2 : .primary)
                }.help("Favorite")
                Menu {
                    ForEach(store.playlists) { pl in Button(pl.name) { store.addToPlaylist(it, pl.id) } }
                    if !store.playlists.isEmpty { Divider() }
                    Button("New Playlist with This") { store.createPlaylist("", with: it) }
                } label: { Image(systemName: "text.badge.plus") }.fixedSize().help("Add to playlist")
                if let p = it.pageURL, let u = URL(string: p) { Button("Source ↗") { NSWorkspace.shared.open(u) } }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 820)
        .onAppear {
            guard it.kind == .video else { return }
            let src: URL? = it.localPath.map { URL(fileURLWithPath: $0) } ?? it.previewURL.flatMap(URL.init(string:))
            if let src { preview.start(src); started = true }
        }
        .onDisappear { preview.stop() }
    }
}

private func mediaDescription(_ it: WallItem) -> String {
    var parts = ["\(it.width)×\(it.height)"]
    if let codec = it.codec { parts.append(codec.uppercased()) }
    if let duration = it.duration { parts.append("\(Int(duration))s video") }
    if let bytes = it.bytes { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
    return parts.joined(separator: " · ")
}
