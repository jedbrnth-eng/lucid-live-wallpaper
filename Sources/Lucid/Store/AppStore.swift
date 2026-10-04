// App state and actions shared by every view.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// MARK: - App store / view model

struct DiscoverState {
    var query = ""
    var items: [WallItem] = []
    var next: Int? = 1
    var loading = false
    var error: String?
    var rejected = 0
    var featured = true
    var generation = 0
}

enum LibFilter: String, CaseIterable { case all = "All", videos = "Videos", photos = "Photos" }

@MainActor final class Store: ObservableObject {
    static let shared = Store()
    let engine = WallpaperEngine()
    let downloader = Downloader()
    @Published var library: [WallItem] = []
    @Published var aerials: [WallItem] = []
    @Published var live: [WallItem] = []
    @Published var discover: [Source: DiscoverState] = [:]
    @Published var keysPresent: Set<KeyName> = []
    @Published var toast: String?
    @Published var favorites: [WallItem] = []
    @Published var playlists: [Playlist] = []
    @Published var activePlaylistID: String? = Pref.activePlaylist
    var downloadsTimer: Timer?
    var folderTimer: Timer?
    var adoptInFlight: Set<String> = []
    var watchSince: Date?
    var seenDownloads: Set<String> = []
    var pendingSizes: [String: Int] = [:]
    private var playlistCursor = -1
    private var history: [String] = []
    private var rotateTimer: Timer?

    init() {
        if let d = try? Data(contentsOf: Paths.library), let l = try? JSONDecoder().decode([WallItem].self, from: d) { library = l }
        aerials = Providers.aerials()
        live = LiveCatalog.load()
        if let d = try? Data(contentsOf: Paths.favorites), let f = try? JSONDecoder().decode([WallItem].self, from: d) { favorites = f }
        if let d = try? Data(contentsOf: Paths.playlists), let p = try? JSONDecoder().decode([Playlist].self, from: d) { playlists = p }
        if let a = activePlaylistID, !playlists.contains(where: { $0.id == a }) { activePlaylistID = nil; Pref.activePlaylist = nil }
        if let cur = engine.state.all?.itemID { history = [cur] }
        refreshKeys()
        for s in Source.discoverable { discover[s] = DiscoverState() }
        scheduleRotation()
        adoptStrayFiles()
        // Keep watching: files dropped into the Lucid folder while the app is open appear within seconds.
        folderTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.adoptStrayFiles() }
        }
    }

    /// Anything dropped straight into the Lucid folder (Media/ or the folder itself) isn't in library.json,
    /// so it would be invisible. On launch, pick those files up and add them to the library.
    func adoptStrayFiles() {
        let fm = FileManager.default
        let known = Set(library.compactMap(\.localPath))
        var stray: [URL] = []
        for dir in [Paths.media, Paths.support] {
            let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                                  options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            while let f = e?.nextObject() as? URL {
                if known.contains(f.path) || adoptInFlight.contains(f.path) || f.lastPathComponent.contains(".loop.") { continue }
                if Media.kind(of: f) == nil { continue }
                if let m = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   Date().timeIntervalSince(m) < 15 { continue }   // still being written
                stray.append(f)
            }
        }
        if !stray.isEmpty { stray.forEach { adoptInFlight.insert($0.path) }; importFiles(stray, move: true, quiet: false) }
    }

    func refreshKeys() { keysPresent = Set(KeyName.allCases.filter { Keychain.get($0) != nil }) }
    func saveKey(_ k: KeyName, _ v: String) {
        Keychain.set(k, v); refreshKeys()
        for s in Source.discoverable where s.needsKey == k { discover[s] = DiscoverState(); load(s, reset: true) }
    }

    private func saveLibrary() { if let d = try? JSONEncoder().encode(library) { try? d.write(to: Paths.library, options: .atomic) } }
    func libraryItem(_ id: String) -> WallItem? { library.first { $0.id == id } }
    func inLibrary(_ id: String) -> Bool { libraryItem(id)?.isLocalReady ?? false }
    func addToLibrary(_ item: WallItem) {
        library.removeAll { $0.id == item.id }
        library.insert(item, at: 0)
        saveLibrary()
    }
    func remove(_ item: WallItem) {
        guard let it = libraryItem(item.id) else { return }
        if let p = it.localPath {
            engine.forget(path: p)
            if p.hasPrefix(Paths.media.path) { try? FileManager.default.removeItem(atPath: p) }
        }
        if let t = it.thumbPath { try? FileManager.default.removeItem(atPath: t) }
        library.removeAll { $0.id == item.id }
        saveLibrary()
        flash("Removed “\(it.title)”")
    }

    // Favorites
    func isFavorite(_ id: String) -> Bool { favorites.contains { $0.id == id } }
    func toggleFavorite(_ item: WallItem) {
        if isFavorite(item.id) { favorites.removeAll { $0.id == item.id }; flash("Removed from Favorites") }
        else { var it = item; it.addedAt = it.addedAt ?? Date(); favorites.insert(it, at: 0); flash("♥ Added to Favorites") }
        if let d = try? JSONEncoder().encode(favorites) { try? d.write(to: Paths.favorites, options: .atomic) }
    }
    var currentItem: WallItem? {
        guard let id = engine.state.all?.itemID ?? engine.state.perScreen.values.first?.itemID else { return nil }
        return findItem(id)
    }
    func findItem(_ id: String) -> WallItem? {
        libraryItem(id) ?? favorites.first { $0.id == id } ?? playlists.lazy.flatMap(\.items).first { $0.id == id }
            ?? live.first { $0.id == id } ?? aerials.first { $0.id == id }
    }

    // Playlists
    private func savePlaylists() { if let d = try? JSONEncoder().encode(playlists) { try? d.write(to: Paths.playlists, options: .atomic) } }
    @discardableResult func createPlaylist(_ name: String, with item: WallItem? = nil) -> Playlist {
        var p = Playlist(name: name.trimmingCharacters(in: .whitespaces).ifEmpty("Playlist \(playlists.count + 1)"))
        if let item { p.items = [item] }
        playlists.append(p); savePlaylists(); flash("Created playlist “\(p.name)”")
        return p
    }
    func addToPlaylist(_ item: WallItem, _ pid: String) {
        guard let i = playlists.firstIndex(where: { $0.id == pid }) else { return }
        if playlists[i].items.contains(where: { $0.id == item.id }) { flash("Already in “\(playlists[i].name)”"); return }
        playlists[i].items.append(item); savePlaylists(); flash("Added to “\(playlists[i].name)”")
    }
    func removeFromPlaylist(_ id: String, _ pid: String) {
        guard let i = playlists.firstIndex(where: { $0.id == pid }) else { return }
        playlists[i].items.removeAll { $0.id == id }; savePlaylists()
    }
    func updatePlaylist(_ p: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == p.id }) else { return }
        playlists[i] = p; savePlaylists()
        if activePlaylistID == p.id { scheduleRotation() }
    }
    func deletePlaylist(_ pid: String) {
        if activePlaylistID == pid { stopPlaylist() }
        playlists.removeAll { $0.id == pid }; savePlaylists()
    }
    var activePlaylist: Playlist? { playlists.first { $0.id == activePlaylistID } }
    func playPlaylist(_ pid: String) {
        guard let p = playlists.first(where: { $0.id == pid }), !p.items.isEmpty else { flash("Add some wallpapers to this playlist first"); return }
        activePlaylistID = pid; Pref.activePlaylist = pid; playlistCursor = -1
        next(); scheduleRotation()
        flash("Playing “\(p.name)” · \(p.shuffle ? "shuffle" : "in order") · every \(Self.intervalLabel(p.minutes))")
    }
    func stopPlaylist() { activePlaylistID = nil; Pref.activePlaylist = nil; scheduleRotation() }
    static func intervalLabel(_ m: Int) -> String {
        m < 60 ? "\(m) min" : m < 1440 ? "\(m / 60) h" : "day"
    }


    private func didApply(_ id: String) {
        if let i = library.firstIndex(where: { $0.id == id }) { library[i].lastAppliedAt = Date(); saveLibrary() }
        if history.last != id { history.append(id); if history.count > 60 { history.removeFirst() } }
    }

    func flash(_ s: String) {
        toast = s
        let cur = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { if self.toast == cur { self.toast = nil } }
    }

    // Discover
    func load(_ s: Source, reset: Bool = false) {
        guard s != .aerials, var st = discover[s] else { return }
        if reset { st.items = []; st.next = 1; st.rejected = 0; st.error = nil; st.generation += 1 }
        guard let page = st.next, !st.loading || reset else { discover[s] = st; return }
        if s.needsKey.map({ !keysPresent.contains($0) }) ?? false { st.error = nil; discover[s] = st; return }
        st.loading = true; st.error = nil
        let gen = st.generation, q = st.query, featured = st.featured
        discover[s] = st
        Task {
            do {
                let r = try await Providers.fetch(s, query: q, page: s == .wikimedia ? (page == 1 ? 0 : page) : page, featured: featured)
                guard var cur = discover[s], cur.generation == gen else { return }
                let have = Set(cur.items.map(\.id))
                cur.items += r.items.filter { !have.contains($0.id) }
                cur.next = r.next; cur.rejected += r.rejected; cur.loading = false
                discover[s] = cur
                // Keep fetching if a page was entirely filtered out by the 4K bar.
                if r.items.isEmpty, r.next != nil, cur.items.count < 12 { load(s) }
            } catch {
                guard var cur = discover[s], cur.generation == gen else { return }
                cur.loading = false; cur.error = error.localizedDescription
                discover[s] = cur
            }
        }
    }
    func search(_ s: Source, _ q: String) {
        discover[s]?.query = q
        load(s, reset: true)
    }

    // Applying
    func setWallpaper(_ item: WallItem, screenKey: String? = nil) {
        if let lib = libraryItem(item.id), lib.isLocalReady, let p = lib.localPath {
            engine.apply(Assignment(itemID: lib.id, title: lib.title, path: p, kind: lib.kind), screenKey: screenKey)
            didApply(lib.id)
            flash("Wallpaper set: \(lib.title)")
            return
        }
        if item.source == .aerials, let p = item.localPath, FileManager.default.fileExists(atPath: p) {
            Task {
                var it = item
                it.thumbPath = await Media.thumbnail(p, .video, id: it.id)
                it.addedAt = Date()
                addToLibrary(it)
                engine.apply(Assignment(itemID: it.id, title: it.title, path: p, kind: .video), screenKey: screenKey)
                didApply(it.id)
                flash("Wallpaper set: \(it.title)")
            }
            return
        }
        flash("Downloading “\(item.title)” in \(item.resLabel)…")
        downloader.start(item) { [weak self] done in
            guard let self else { return }
            self.addToLibrary(done)
            if let p = done.localPath {
                self.engine.apply(Assignment(itemID: done.id, title: done.title, path: p, kind: done.kind), screenKey: screenKey)
                self.didApply(done.id)
                self.flash("Wallpaper set: \(done.title)")
            }
        }
    }
    func download(_ item: WallItem) {
        if item.source == .aerials, item.localPath != nil { setLibraryOnly(item); return }
        downloader.start(item) { [weak self] done in self?.addToLibrary(done); self?.flash("Saved to library: \(done.title)") }
    }
    private func setLibraryOnly(_ item: WallItem) {
        Task {
            var it = item
            if let p = it.localPath { it.thumbPath = await Media.thumbnail(p, .video, id: it.id) }
            it.addedAt = Date()
            addToLibrary(it); flash("Added to library: \(it.title)")
        }
    }

    enum ImportResult { case added(Bool), duplicate, unsupported, failed(String) }

    /// Drag & drop, Dock and Downloads-folder imports all land here. Files are COPIED
    /// into the app's Media folder so deleting ~/Downloads never breaks a wallpaper. Formats AVFoundation
    /// can't play (WebM, MKV, AVI…) are converted to HEVC.
    func importFiles(_ urls: [URL], move: Bool = false, site: String? = nil, page: String? = nil, quiet: Bool = false) {
        let local = urls.filter(\.isFileURL)
        guard !local.isEmpty else { return }
        Task {
            var files: [URL] = []
            for u in local {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                    let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    while let f = e?.nextObject() as? URL { if Media.kind(of: f) != nil { files.append(f) } }
                } else { files.append(u) }
            }
            if files.count > 1 || !quiet { flash(files.count > 1 ? "Importing \(files.count) files…" : "Importing \(files.first?.lastPathComponent ?? "")…") }
            var added = 0, low = 0, dup = 0, unsup = 0
            var failed: [String] = []
            for u in files {
                switch await importOne(u, move: move, site: site, page: page) {
                case .added(let is4K): added += 1; if !is4K { low += 1 }
                case .duplicate: dup += 1
                case .unsupported: unsup += 1
                case .failed(let m): failed.append("\(u.lastPathComponent): \(m)")
                }
            }
            var msg = added == 1 ? "Added to your library" : "Imported \(added) wallpapers"
            if added == 0 { msg = dup > 0 ? "Already in your library" : "Nothing imported" }
            if low > 0 { msg += " · \(low) below 4K (flagged)" }
            if unsup > 0 { msg += " · \(unsup) not a video/photo" }
            if !failed.isEmpty { msg += " · failed: " + failed.prefix(2).joined(separator: "; ") }
            flash(msg)
        }
    }

    func importOne(_ u: URL, move: Bool, site: String?, page: String?) async -> ImportResult {
        guard let k = Media.kind(of: u), Media.looksLikeMedia(u) else { return .unsupported }
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: u.path)[.size] as? Int64) ?? 0
        let base = u.deletingPathExtension().lastPathComponent
        let id = "local:" + Paths.safe("\(base)-\(size)")
        if inLibrary(id) && (libraryItem(id)?.isLocalReady ?? false) { if move { try? fm.removeItem(at: u) }; return .duplicate }
        let ext = u.pathExtension.lowercased()
        var needsTx = false
        if k == .video {
            let playable = (try? await AVURLAsset(url: u).load(.isPlayable)) ?? false
            needsTx = !playable || ["webm", "mkv", "avi", "wmv", "flv", "ogv"].contains(ext)
        }
        var dest = Paths.media.appendingPathComponent(Paths.safe(base) + "-" + String(size, radix: 36) + "." + (needsTx ? "mp4" : ext))
        do {
            if u.standardizedFileURL.path.hasPrefix(Paths.media.standardizedFileURL.path) { dest = u }
            else if needsTx {
                try await Transcoder.toHEVC(u, dest)
                if move { try? fm.removeItem(at: u) }
            } else {
                try? fm.removeItem(at: dest)
                if move { try fm.moveItem(at: u, to: dest) } else { try fm.copyItem(at: u, to: dest) }
            }
        } catch { return .failed(error.localizedDescription) }
        let dims = await Media.dims(dest.path, k) ?? (0, 0)
        var it = WallItem(id: id, source: .local, kind: k, title: Importer.niceTitle(base),
                          width: dims.0, height: dims.1,
                          license: site.map { "Downloaded from \($0) for personal use. Rights stay with the original artist/owner." } ?? "Your file",
                          fileExt: dest.pathExtension, localPath: dest.path)
        it.author = site
        it.pageURL = page
        it.thumbPath = await Media.thumbnail(dest.path, k, id: id)
        it.bytes = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int64)
        it.duration = k == .video ? await Media.duration(dest.path) : nil
        it.addedAt = Date()
        it.tags = site.map { [$0.components(separatedBy: ".").first ?? $0] }
        addToLibrary(it)
        return .added(it.is4K)
    }

    // Watch ~/Downloads: new ≥4K videos/photos are copied into the library automatically (opt-in).
    func startDownloadsWatcher() {
        downloadsTimer?.invalidate(); downloadsTimer = nil
        guard Pref.watchDownloads else { return }
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        if watchSince == nil { watchSince = Date() }
        downloadsTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanDownloads(dir) }
        }
    }
    private func scanDownloads(_ dir: URL) {
        guard let since = watchSince, let items = try? FileManager.default.contentsOfDirectory(at: dir,
              includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return }
        for f in items where Media.kind(of: f) != nil && !seenDownloads.contains(f.path) {
            let v = try? f.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            guard let c = v?.creationDate, c > since, let sz = v?.fileSize, sz > 0 else { continue }
            if pendingSizes[f.path] != sz { pendingSizes[f.path] = sz; continue }   // wait until the size stops changing
            seenDownloads.insert(f.path); pendingSizes[f.path] = nil
            Task {
                guard let k = Media.kind(of: f), let d = await Media.dims(f.path, k) else { return }
                if max(d.0, d.1) >= 3840 && min(d.0, d.1) >= 2160 { importFiles([f], quiet: true) }
            }
        }
    }

    // Rotation / next
    func next() {
        let cur = engine.state.all?.itemID
        if let p = activePlaylist, !p.items.isEmpty {
            let idx: Int
            if p.shuffle {
                let others = p.items.indices.filter { p.items[$0].id != cur }
                idx = others.randomElement() ?? 0
            } else { idx = (playlistCursor + 1) % p.items.count }
            playlistCursor = idx
            let it = p.items[idx]
            setWallpaper(libraryItem(it.id) ?? it)
            return
        }
        let pool = library.filter { $0.isLocalReady && $0.id != cur }
        guard let pick = pool.randomElement() else { flash("Add more wallpapers to your library first"); return }
        setWallpaper(pick)
    }
    func previous() {
        guard history.count >= 2 else { flash("No previous wallpaper yet"); return }
        history.removeLast()
        let id = history.removeLast()
        guard let it = findItem(id) else { flash("Previous wallpaper is no longer available"); return }
        setWallpaper(it)
    }
    func scheduleRotation() {
        rotateTimer?.invalidate(); rotateTimer = nil
        let m = activePlaylist?.minutes ?? Pref.rotateMinutes
        guard m > 0 else { return }
        rotateTimer = Timer.scheduledTimer(withTimeInterval: Double(m) * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() } }
    }

    var libraryBytes: Int64 { library.filter { $0.localPath?.hasPrefix(Paths.media.path) ?? false }.compactMap(\.bytes).reduce(0, +) }

    // Self-test (headless): `open -a "Lucid" --args -selftest YES`
    func runSelfTest() async -> [String: Any] {
        var r: [String: Any] = [:]
        let a = aerials
        r["aerials_count"] = a.count
        r["live_count"] = live.count
        r["live_all_4k"] = live.allSatisfy(\.is4K)
        r["live_by_collection"] = Dictionary(grouping: live, by: { $0.author ?? "?" }).mapValues(\.count)
        r["live_unique_ids"] = Set(live.map(\.id)).count == live.count
        r["live_codecs_ok"] = live.allSatisfy { ["h264", "hevc"].contains($0.codec ?? "") || ($0.codec == "webm" && Transcoder.ffmpeg != nil) }
        r["live_all_have_credit_and_terms"] = live.allSatisfy { ($0.creditFull ?? "").count > 2 && $0.termsURL != nil && $0.pageURL != nil }
        r["aerials_all_4k_declared"] = a.allSatisfy(\.is4K)
        r["aerials_cached_on_mac"] = a.filter { $0.localPath != nil }.count
        if let c = a.first(where: { $0.localPath != nil }), let p = c.localPath, let d = await Media.dims(p, .video) {
            r["aerials_probe"] = ["title": c.title, "width": d.0, "height": d.1]
        }
        do {
            let w = try await Providers.wikimedia("night city", offset: 0, featured: false)
            r["wikimedia_count"] = w.items.count
            r["wikimedia_rejected_below_4k"] = w.rejected
            r["wikimedia_all_4k"] = w.items.allSatisfy(\.is4K)
            r["wikimedia_sample"] = w.items.prefix(3).map { "\($0.title) \($0.width)x\($0.height) \($0.license ?? "")" }
            let f = try await Providers.wikimedia("", offset: 0, featured: true)
            r["wikimedia_featured_count"] = f.items.count
        } catch { r["wikimedia_error"] = error.localizedDescription }
        do {
            let n = try await Providers.nasa("nebula", page: 1)
            r["nasa_count"] = n.items.count
            r["nasa_rejected_below_4k"] = n.rejected
            r["nasa_all_4k"] = n.items.allSatisfy(\.is4K)
            r["nasa_sample"] = n.items.prefix(3).map { "\($0.title) \($0.width)x\($0.height)" }
        } catch { r["nasa_error"] = error.localizedDescription }
        for (k, s) in [(KeyName.pixabay, Source.pixabayVideo)] {
            guard keysPresent.contains(k) else { r["\(s.rawValue)"] = "no key"; continue }
            do { let p = try await Providers.fetch(s, query: "city night", page: 1, featured: false)
                r["\(s.rawValue)"] = ["count": p.items.count, "rejected": p.rejected, "all_4k": p.items.allSatisfy(\.is4K)]
            } catch { r["\(s.rawValue)"] = "error: \(error.localizedDescription)" }
        }
        r["favorites"] = favorites.count
        r["playlists"] = playlists.count
        r["screens"] = NSScreen.screens.map { "\($0.localizedName) \($0.pixelSize)" }
        return r
    }
}
