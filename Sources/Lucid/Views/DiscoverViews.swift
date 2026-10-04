// Discover pages: Live 4K, Apple Aerials and online sources.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

struct AerialsView: View {
    @EnvironmentObject var store: Store
    @State private var cat = "All"
    @State private var q = ""
    @State private var selected: WallItem?
    var body: some View {
        let cats = ["All"] + Array(Set(store.aerials.compactMap(\.category))).sorted() + ["On this Mac"]
        let items = store.aerials.filter { a in
            (cat == "All" || (cat == "On this Mac" ? a.localPath != nil : a.category == cat)) &&
            (q.isEmpty || a.title.localizedCaseInsensitiveContains(q) || (a.author ?? "").localizedCaseInsensitiveContains(q))
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Header(title: "Apple Aerials", subtitle: Source.aerials.blurb + " Each film is ~300–600 MB; ones already on this Mac apply instantly.")
                HStack {
                    TextField("Search aerials (e.g. Dubai, ocean, night)", text: $q).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    Text("\(items.count) of \(store.aerials.count)").font(.caption).foregroundStyle(.secondary)
                }
                Chips(options: cats, selected: cat) { cat = $0 }
                if store.aerials.isEmpty {
                    Text("Apple's Aerials catalog wasn't found on this Mac. Open System Settings → Wallpaper once so macOS downloads it.")
                        .foregroundStyle(.secondary)
                }
                Grid(items: items, selected: $selected)
            }.padding(24)
        }
        .sheet(item: $selected) { DetailView(item: $0) }
    }
}

struct LiveView: View {
    @EnvironmentObject var store: Store
    @State private var col = "All"
    @State private var tag = "All"
    @State private var q = ""
    @State private var selected: WallItem?
    var body: some View {
        let cols = ["All"] + Array(Set(store.live.compactMap(\.author))).sorted()
        let tags = ["All"] + Array(Set(store.live.compactMap(\.category))).sorted()
        let items = store.live.filter { a in
            (col == "All" || a.author == col) && (tag == "All" || a.category == tag) &&
            (q.isEmpty || a.title.localizedCaseInsensitiveContains(q))
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Header(title: "Live 4K", subtitle: Source.live.blurb)
                HStack {
                    TextField("Search (e.g. nebula, galaxy, Earth, zoom)", text: $q).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    Text("\(items.count) of \(store.live.count) clips").font(.caption).foregroundStyle(.secondary)
                }
                Chips(options: cols, selected: col) { col = $0 }
                Chips(options: tags, selected: tag) { tag = $0 }
                if store.live.isEmpty {
                    Text("The live catalog is empty. Run tools/build_catalog.py to rebuild it.").foregroundStyle(.secondary)
                }
                Grid(items: items, selected: $selected)
            }.padding(24)
        }
        .sheet(item: $selected) { DetailView(item: $0) }
    }
}

struct DiscoverView: View {
    let source: Source
    @EnvironmentObject var store: Store
    @State private var q = ""
    @State private var selected: WallItem?
    var body: some View {
        let st = store.discover[source] ?? DiscoverState()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Header(title: source.label, subtitle: source.blurb)
                if let k = source.needsKey, !store.keysPresent.contains(k) {
                    KeyPrompt(key: k)
                } else {
                    HStack(spacing: 10) {
                        TextField("Search \(source.label)…", text: $q).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
                            .onSubmit { store.search(source, q) }
                        Button("Search") { store.search(source, q) }
                        if source == .wikimedia {
                            Toggle("Featured pictures only", isOn: Binding(get: { st.featured }, set: { store.discover[source]?.featured = $0; store.load(source, reset: true) }))
                                .toggleStyle(.checkbox)
                        }
                        Spacer()
                        if st.rejected > 0 { Text("\(st.rejected) hidden: below 4K").font(.caption).foregroundStyle(.orange) }
                    }
                    Chips(options: source.quickQueries, selected: st.query) { o in q = o; store.search(source, o) }
                    if let e = st.error {
                        Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Button("Retry") { store.load(source) }
                    }
                    if !st.loading && st.items.isEmpty && st.error == nil && st.next == nil {
                        Text("No 4K results for “\(st.query)”. Try a broader word.").foregroundStyle(.secondary)
                    }
                    Grid(items: st.items, selected: $selected)
                    HStack {
                        Spacer()
                        if st.loading { ProgressView() }
                        else if st.next != nil && !st.items.isEmpty { Button("Load more") { store.load(source) }.onAppear { store.load(source) } }
                        Spacer()
                    }.padding(.vertical, 8)
                }
            }.padding(24)
        }
        .onAppear {
            q = st.query
            if st.items.isEmpty && !st.loading { store.load(source, reset: true) }
        }
        .sheet(item: $selected) { DetailView(item: $0) }
    }
}

struct KeyPrompt: View {
    let key: KeyName
    @EnvironmentObject var store: Store
    @State private var value = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("One-time setup: free \(key.label) API key", systemImage: "key.fill").font(.headline)
            Text("\(key.label) requires a free personal API key. Sign up, copy your key, and paste it here. It's stored in your macOS Keychain and only sent to \(key.label).")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                SecureField("\(key.label) API key", text: $value).textFieldStyle(.roundedBorder).frame(maxWidth: 380)
                Button("Save") { store.saveKey(key, value); value = "" }.disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                Link("Get a free key ↗", destination: key.signupURL)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.35)))
    }
}
