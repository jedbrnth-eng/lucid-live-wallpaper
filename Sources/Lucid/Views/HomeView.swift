// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Home: a featured hero that plays, then rows you scroll sideways (recently used, most used, featured, favorites,
// new, and one per category). Which rows show and in what order is HomeBuilder (pure, unit-tested).
import SwiftUI
import AppKit

struct HomeView: View {
    /// Navigate to a full page ("See all").
    var go: (Nav) -> Void = { _ in }
    @EnvironmentObject var store: Store
    @State private var selected: WallItem?

    var body: some View {
        let input = store.homeInput()
        let rows = HomeBuilder.rows(input)
        let hero = HomeBuilder.hero(input)
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 34) {
                if let hero { HeroBanner(item: hero, open: { selected = hero }) } else { welcome }
                if store.usage.isEmpty && store.library.isEmpty { firstRunHint }
                ForEach(rows) { row in
                    HomeRowView(row: row, open: { selected = $0 }, seeAll: destination(row.kind).map { d in { go(d) } })
                }
            }
            .padding(.vertical, Theme.pad)
        }
        .scrollIndicators(.automatic)
        .sheet(item: $selected) { DetailView(item: $0) }
    }

    private func destination(_ k: HomeRow.Kind) -> Nav? {
        switch k {
        case .continueWatching, .mostUsed: return .recents
        case .featured: return .discover(.live)
        case .favorites: return .favorites
        case .recentlyAdded: return .library(.all)
        case .category(let c):
            if c == HomeBuilder.aerialsTitle { return .discover(.aerials) }
            if c == HomeBuilder.myFilesTitle { return .library(.all) }
            return .liveTheme(c)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your desktop,").font(.system(size: 44, weight: .bold)).tracking(-1.2).foregroundStyle(Theme.ink)
            Text("wide awake.").font(.system(size: 44, weight: .regular, design: .serif).italic()).foregroundStyle(Theme.glow)
            Text("Pick a moving 4K wallpaper below, or drop your own videos and photos anywhere in this window.")
                .font(.title3).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.pad)
        .accessibilityElement(children: .combine)
    }

    private var firstRunHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Theme.cyan)
            Text("New here? Hover any clip to preview it once it's on this Mac. Apple Aerials already on your Mac play right away.")
                .font(.callout).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.pad)
    }
}

// MARK: - Hero

struct HeroBanner: View {
    let item: WallItem
    var open: () -> Void
    @EnvironmentObject var store: Store
    @EnvironmentObject var dl: Downloader
    @EnvironmentObject var engine: LucidEngine

    var body: some View {
        let it = store.libraryItem(item.id) ?? item
        let current = engine.currentAssignments.contains { $0.itemID == it.id }
        let onMac = it.isLocalReady
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay(RemoteImage(url: it.thumbURL, localPath: it.thumbPath))
                .overlay(PreviewLayer(item: it, wanted: true, pinned: true, size: .large, dwell: 0))
                .clipped()
            LinearGradient(colors: [.clear, Theme.bg.opacity(0.35), Theme.bg.opacity(0.92)], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Theme.bg.opacity(0.7), .clear], startPoint: .leading, endPoint: .center)
            VStack(alignment: .leading, spacing: 12) {
                MonoPill(text: store.featuredIDs.contains(it.id) ? "FEATURED · \(it.source.label)" : "ON THIS MAC · \(it.source.label)")
                Text(it.title).font(.system(size: 38, weight: .bold)).tracking(-1).foregroundStyle(Theme.ink)
                    .lineLimit(2).shadow(color: .black.opacity(0.4), radius: 8)
                Text([it.author, it.category, it.duration.map { "\(Int($0))s loop" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(Theme.muted)
                HStack(spacing: 10) {
                    Button { store.setWallpaper(it) } label: {
                        Label(current ? "On Your Desktop" : onMac ? "Apply" : "Download & Apply", systemImage: current ? "checkmark" : "sparkles.tv")
                    }
                    .buttonStyle(.pillPrimary)
                    .disabled(current || dl.progress[it.id] != nil)
                    .help(onMac ? "Set as wallpaper on all displays" : "Download in full quality, then set on all displays")
                    Button(action: open) { Label("Details", systemImage: "info.circle") }.buttonStyle(.pill)
                    Button { store.toggleFavorite(it) } label: {
                        Image(systemName: store.isFavorite(it.id) ? "heart.fill" : "heart")
                            .foregroundStyle(store.isFavorite(it.id) ? accent2 : Theme.ink)
                    }
                    .buttonStyle(.pill)
                    .accessibilityLabel(store.isFavorite(it.id) ? "Remove from favorites" : "Add to favorites")
                    DownloadStatusRow(id: it.id, compact: true)
                }
                .padding(.top, 4)
            }
            .padding(30)
        }
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line))
        .shadow(color: Theme.violet.opacity(0.25), radius: 30, y: 12)
        .padding(.horizontal, Theme.pad)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Featured: \(it.title)")
    }
}

// MARK: - Rows

struct HomeRowView: View {
    let row: HomeRow
    var open: (WallItem) -> Void
    var seeAll: (() -> Void)?
    @State private var position: String?
    @State private var hover = false
    static let cardWidth: CGFloat = 288

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.title).font(.system(size: 21, weight: .semibold)).tracking(-0.4).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(row.subtitle).font(.callout).foregroundStyle(Theme.faint)
                Spacer()
                if let seeAll {
                    Button(action: seeAll) { HStack(spacing: 3) { Text("See all"); Image(systemName: "chevron.right") } }
                        .buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(Theme.muted)
                        .accessibilityLabel("See all \(row.title)")
                }
            }
            .padding(.horizontal, Theme.pad)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Theme.gap) {
                    ForEach(row.items) { item in
                        Card(item: item, onOpen: { open(item) })
                            .frame(width: Self.cardWidth)
                            .onTapGesture { open(item) }
                            .contextMenu { ItemMenu(item: item) }
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Theme.pad)
                .padding(.vertical, 8)   // room for the hover lift and glow
            }
            .scrollIndicators(.never)
            .scrollPosition(id: $position, anchor: .leading)
            .overlay(alignment: .leading) { arrow(-1) }
            .overlay(alignment: .trailing) { arrow(1) }
        }
        .onHover { hover = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.title), \(row.items.count) wallpaper\(row.items.count == 1 ? "" : "s")")
    }

    /// Netflix-style paging arrows for mouse users (trackpads scroll sideways anyway).
    @ViewBuilder private func arrow(_ dir: Int) -> some View {
        let ids = row.items.map(\.id)
        let i = position.flatMap { ids.firstIndex(of: $0) } ?? 0
        let canGo = dir < 0 ? i > 0 : i + 3 < ids.count
        if hover && canGo {
            Button {
                let j = max(0, min(ids.count - 1, i + dir * 3))
                withAnimation(.easeInOut(duration: 0.35)) { position = ids[j] }
            } label: {
                Image(systemName: dir < 0 ? "chevron.left" : "chevron.right")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.ultraThinMaterial)).overlay(Circle().stroke(Theme.line))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .accessibilityLabel(dir < 0 ? "Scroll \(row.title) back" : "Scroll \(row.title) forward")
            .transition(.opacity)
        }
    }
}
