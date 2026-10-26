// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

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
    let engine: LucidEngine
    let dayNight: DayNightController
    let audio: AudioReactive
    let weather: WeatherService
    let downloader = Downloader()
    @Published var library: [WallItem] = []
    @Published var aerials: [WallItem] = []
    @Published var live: [WallItem] = []
    @Published var discover: [Source: DiscoverState] = [:]
    @Published var keysPresent: Set<KeyName> = []
    @Published var toast: String?
    @Published var favorites: [WallItem] = []
    @Published var playlists: [Playlist] = []
    /// Playing playlists, one per scope (display key, or "*" for all displays). Saved in playback.json.
    @Published private(set) var runs: [String: PlaylistRun] = [:]
    var downloadsTimer: Timer?
    var folderTimer: Timer?
    var adoptInFlight: Set<String> = []
    var watchSince: Date?
    var seenDownloads: Set<String> = []
    var pendingSizes: [String: Int] = [:]
    private var history: [String] = []
    private var rotateTimer: Timer?

    init() {
        let e = LucidEngine()
        engine = e
        dayNight = DayNightController(engine: e)   // sets the phase before the first refresh
        audio = AudioReactive(engine: e)
        weather = WeatherService(engine: e)
        if let d = try? Data(contentsOf: Paths.library) { library = SavedData.items(d) }
        aerials = Providers.aerials()
        live = LiveCatalog.load()
        if let d = try? Data(contentsOf: Paths.favorites) { favorites = SavedData.items(d) }
        if let d = try? Data(contentsOf: Paths.playlists) { playlists = SavedData.playlists(d) }
        if let d = try? Data(contentsOf: Paths.playback) { runs = PlaybackState.decode(d).runs }
        // 1.2.0 and earlier kept one playlist for all displays in a preference.
        if runs.isEmpty, let a = Pref.activePlaylist, let p = playlists.first(where: { $0.id == a }), !p.items.isEmpty {
            var r = PlaylistRun(playlistID: a, ids: p.items.map(\.id), shuffle: p.shuffle, now: Date())
            if let cur = engine.state.all?.itemID, let i = r.order.firstIndex(of: cur) { r.position = i }
            runs[EngineState.allKey] = r
        }
        runs = runs.filter { kv in playlists.contains { $0.id == kv.value.playlistID } }
        syncPlaylistScopes()
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
            // Only Lucid's own copies are deleted; a file imported "in place" (or anything outside Media/) never is.
            if it.referenced != true, ImportPolicy.isContained(URL(fileURLWithPath: p).resolvingSymlinksInPath().path,
                                                             in: Paths.media.resolvingSymlinksInPath().path) {
                try? FileManager.default.removeItem(atPath: p)
            }
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
        guard let id = engine.currentAssignments.first?.itemID else { return nil }
        return findItem(id)
    }
    func findItem(_ id: String) -> WallItem? {
        libraryItem(id) ?? favorites.first { $0.id == id } ?? playlists.lazy.flatMap(\.items).first { $0.id == id }
            ?? live.first { $0.id == id } ?? aerials.first { $0.id == id }
    }

    /// An assignment that can go on screen right now (used by Day/Night): the item must already be on this Mac.
    func readyAssignment(for item: WallItem) -> Assignment? {
        guard let lib = libraryItem(item.id) ?? (item.isLocalReady ? item : nil), lib.isLocalReady, let p = lib.localPath else { return nil }
        return Assignment(itemID: lib.id, title: lib.title, path: p, kind: lib.kind, options: lib.options)
    }

    /// Per-wallpaper fit / crop focus / speed. Saved with the library item and applied live wherever it is on screen.
    func setOptions(_ item: WallItem, _ o: WallpaperOptions) {
        guard let i = library.firstIndex(where: { $0.id == item.id }) else { return }
        library[i].options = o.isDefault ? nil : o
        saveLibrary()
        engine.updateOptions(itemID: item.id, library[i].options)
    }

    func setDayNight(day: WallItem, night: WallItem, dawn: WallItem? = nil, dusk: WallItem? = nil, screenKey: String?) {
        guard let d = readyAssignment(for: day), let n = readyAssignment(for: night) else {
            flash("Both Day and Night wallpapers must be on this Mac first"); return
        }
        engine.applyDayNight(DayNightRule(day: d, night: n, dawn: dawn.flatMap(readyAssignment(for:)), dusk: dusk.flatMap(readyAssignment(for:))),
                             screenKey: screenKey)
        flash("Day/Night set: \(d.title) by day, \(n.title) at night")
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
        var rng = SystemRandomNumberGenerator()
        for (scope, var r) in runs where r.playlistID == p.id {
            let before = r.current
            r.reconcile(ids: p.items.map(\.id), shuffle: p.shuffle, rng: &rng)
            runs[scope] = r
            if r.current == nil { runs[scope] = nil } else if r.current != before { show(scope) }
        }
        saveRuns()
    }
    func deletePlaylist(_ pid: String) {
        stopPlaylist(pid)
        playlists.removeAll { $0.id == pid }; savePlaylists()
    }
    /// The playlist playing on all displays (the one the menu bar and toolbar talk about).
    var activePlaylistID: String? { runs[EngineState.allKey]?.playlistID ?? runs.values.first?.playlistID }
    var activePlaylist: Playlist? { playlists.first { $0.id == activePlaylistID } }
    func isPlaying(_ pid: String) -> Bool { runs.values.contains { $0.playlistID == pid } }
    /// Where a playlist is playing, for display: "All displays" or display names.
    func playingWhere(_ pid: String) -> String {
        let scopes = runs.filter { $0.value.playlistID == pid }.map(\.key)
        if scopes.contains(EngineState.allKey) { return "all displays" }
        return scopes.map { k in NSScreen.screens.first { $0.stableKey == k }?.localizedName ?? "a disconnected display" }.sorted().joined(separator: ", ")
    }

    /// Start a playlist on every display (screenKey nil) or on one display.
    func playPlaylist(_ pid: String, screenKey: String? = nil) {
        guard let p = playlists.first(where: { $0.id == pid }), !p.items.isEmpty else { flash("Add some wallpapers to this playlist first"); return }
        let scope = screenKey ?? EngineState.allKey
        if screenKey == nil { runs = [:] }   // "all displays" replaces every per-display playlist, like setting one wallpaper for all
        runs[scope] = PlaylistRun(playlistID: pid, ids: p.items.map(\.id), shuffle: p.shuffle, now: Date())
        saveRuns(); syncPlaylistScopes()
        show(scope)
        let when = PlaylistScheduler.sanitize(p.times).isEmpty ? "every \(Self.intervalLabel(p.minutes))" : "at set times"
        flash("Playing “\(p.name)” · \(p.shuffle ? "shuffle" : "in order") · \(when)")
    }
    /// Stop one playlist everywhere, or (nil) every playlist.
    func stopPlaylist(_ pid: String? = nil) {
        runs = runs.filter { pid != nil && $0.value.playlistID != pid }
        saveRuns(); syncPlaylistScopes()
    }
    private func saveRuns() {
        if let d = try? JSONEncoder().encode(PlaybackState(runs: runs)) { try? d.write(to: Paths.playback, options: .atomic) }
        Pref.activePlaylist = runs[EngineState.allKey]?.playlistID
    }
    private func syncPlaylistScopes() { engine.crossfadeScopes = Set(runs.keys); scheduleRotation() }

    /// Put a run's current item on its scope.
    private func show(_ scope: String) {
        guard let r = runs[scope], let id = r.current, let p = playlists.first(where: { $0.id == r.playlistID }),
              let it = p.items.first(where: { $0.id == id }) else { return }
        let others = Set(runs.keys).subtracting([EngineState.allKey])
        setWallpaper(libraryItem(it.id) ?? it, screenKey: scope == EngineState.allKey ? nil : scope, keepScreens: others)
    }
    private func step(_ scope: String, forward: Bool) {
        guard var r = runs[scope], let p = playlists.first(where: { $0.id == r.playlistID }) else { return }
        var rng = SystemRandomNumberGenerator()
        if forward { r.advance(ids: p.items.map(\.id), shuffle: p.shuffle, now: Date(), rng: &rng) } else { r.back(); r.changedAt = Date() }
        runs[scope] = r; saveRuns()
        show(scope)
    }
    /// Every 30 s: advance any playlist whose next change is due (also catches up after sleep or a relaunch).
    func playlistTick(now: Date = Date()) {
        for (scope, r) in runs {
            guard let p = playlists.first(where: { $0.id == r.playlistID }) else { continue }
            if PlaylistScheduler.isDue(r, minutes: p.minutes, times: p.times, timeZone: .current, now: now) { step(scope, forward: true) }
        }
    }
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
    func setWallpaper(_ item: WallItem, screenKey: String? = nil, keepScreens: Set<String> = []) {
        if let lib = libraryItem(item.id), lib.isLocalReady, let p = lib.localPath {
            engine.apply(Assignment(itemID: lib.id, title: lib.title, path: p, kind: lib.kind, options: lib.options), screenKey: screenKey, keepScreens: keepScreens)
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
                engine.apply(Assignment(itemID: it.id, title: it.title, path: p, kind: .video), screenKey: screenKey, keepScreens: keepScreens)
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
                self.engine.apply(Assignment(itemID: done.id, title: done.title, path: p, kind: done.kind), screenKey: screenKey, keepScreens: keepScreens)
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
    static let maxImportFiles = 500

    /// Drag & drop, Dock and Downloads-folder imports all land here. Files are COPIED
    /// into the app's Media folder so deleting ~/Downloads never breaks a wallpaper. Formats AVFoundation
    /// can't play (WebM, MKV, AVI…) are converted to HEVC.
    func importFiles(_ urls: [URL], move: Bool = false, site: String? = nil, page: String? = nil, quiet: Bool = false) {
        let local = urls.filter(\.isFileURL)
        guard !local.isEmpty else { return }
        Task {
            var files: [URL] = []
            for u in local.prefix(Self.maxImportFiles) {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                    // Only files really inside the chosen folder: symlinks and hidden files are skipped.
                    files += ImportPolicy.mediaFiles(in: u, limit: Self.maxImportFiles - files.count)
                } else { files.append(u) }
                if files.count >= Self.maxImportFiles { break }
            }
            if files.count > 1 || !quiet { flash(files.count > 1 ? "Importing \(files.count) files…" : "Importing \(files.first?.lastPathComponent ?? "")…") }
            var added = 0, low = 0, dup = 0, unsup = 0
            var failed: [String] = []
            var rejected: [String] = []
            for u in files {
                switch await importOne(u, move: move, site: site, page: page) {
                case .added(let is4K): added += 1; if !is4K { low += 1 }
                case .duplicate: dup += 1
                case .unsupported: unsup += 1; rejected.append(u.lastPathComponent)
                case .failed(let m): failed.append("\(u.lastPathComponent): \(m)")
                }
            }
            var msg = added == 1 ? "Added to your library" : "Imported \(added) wallpapers"
            if added == 0 { msg = dup > 0 ? "Already in your library" : "Nothing imported" }
            if low > 0 { msg += " · \(low) below 4K (flagged)" }
            if unsup > 0 { msg += unsup == 1 && files.count == 1 ? " · “\(rejected[0])” isn't a video or photo Lucid can use" : " · \(unsup) not a video/photo" }
            if !failed.isEmpty { msg += " · failed: " + failed.prefix(2).joined(separator: "; ") }
            flash(msg)
        }
    }

    func importOne(_ input: URL, move: Bool, site: String?, page: String?) async -> ImportResult {
        let fm = FileManager.default
        // A chosen symlink counts as the file it points to; anything that isn't a regular file is refused.
        let u = input.resolvingSymlinksInPath()
        guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return .unsupported }
        let size = (try? fm.attributesOfItem(atPath: u.path)[.size] as? Int64) ?? 0
        let ext = u.pathExtension.lowercased()
        let k: Kind
        switch ImportPolicy.check(ext: ext, size: size, header: Media.header(u)) {
        case .ok(let kind): k = kind
        case .rejected(let why): return ImportPolicy.kind(forExtension: ext) == nil ? .unsupported : .failed(why)
        }
        let base = u.deletingPathExtension().lastPathComponent
        let id = "local:" + Paths.safe("\(base)-\(size)")
        if inLibrary(id) && (libraryItem(id)?.isLocalReady ?? false) { if move { try? fm.removeItem(at: u) }; return .duplicate }
        // Damaged files: make sure AVFoundation / ImageIO can actually read it before copying anything.
        var needsTx = false
        if k == .video {
            let asset = AVURLAsset(url: u)
            let playable = (try? await asset.load(.isPlayable)) ?? false
            needsTx = !playable || ["webm", "mkv", "avi", "wmv", "flv", "ogv"].contains(ext)
            if !needsTx, await Media.dims(u.path, .video).map({ $0.0 > 0 && $0.1 > 0 }) != true {
                return .failed("damaged, or no video track")
            }
        } else if await Media.dims(u.path, .image) == nil { return .failed("damaged, or not a photo format macOS can read") }
        let inMedia = ImportPolicy.isContained(u.path, in: Paths.media.resolvingSymlinksInPath().path)
        let reference = Pref.importInPlace && !move && !needsTx && !inMedia
        var dest = Paths.media.appendingPathComponent(ImportPolicy.destinationName(base: base, size: size, ext: needsTx ? "mp4" : ext))
        guard ImportPolicy.isContained(dest.path, in: Paths.media.path) else { return .failed("bad file name") }
        do {
            if inMedia || reference { dest = u }
            else if needsTx {
                do { try await Transcoder.toHEVC(u, dest) } catch {
                    try? fm.removeItem(at: dest)   // never leave a half-written file behind
                    return .failed(Transcoder.ffmpeg == nil ? error.localizedDescription : "damaged, or a video format Lucid can't convert")
                }
                if move { try? fm.removeItem(at: u) }
                if await Media.dims(dest.path, .video) == nil { try? fm.removeItem(at: dest); return .failed("could not convert this video") }
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
        it.referenced = reference ? true : nil
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
        if !runs.isEmpty { for k in runs.keys.sorted() { step(k, forward: true) }; return }
        let cur = engine.state.all?.itemID
        let pool = library.filter { $0.isLocalReady && $0.id != cur }
        guard let pick = pool.randomElement() else { flash("Add more wallpapers to your library first"); return }
        setWallpaper(pick)
    }
    func previous() {
        if !runs.isEmpty { for k in runs.keys.sorted() { step(k, forward: false) }; return }
        guard history.count >= 2 else { flash("No previous wallpaper yet"); return }
        history.removeLast()
        let id = history.removeLast()
        guard let it = findItem(id) else { flash("Previous wallpaper is no longer available"); return }
        setWallpaper(it)
    }
    /// Playlists are checked every 30 s; without one, the Settings auto-change timer picks a random library item.
    func scheduleRotation() {
        rotateTimer?.invalidate(); rotateTimer = nil
        if !runs.isEmpty {
            rotateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.playlistTick() } }
            playlistTick()
            return
        }
        let m = Pref.rotateMinutes
        guard m > 0 else { return }
        rotateTimer = Timer.scheduledTimer(withTimeInterval: Double(m) * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() } }
    }

    var libraryBytes: Int64 { library.filter { $0.referenced != true && ($0.localPath?.hasPrefix(Paths.media.path) ?? false) }.compactMap(\.bytes).reduce(0, +) }

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
        r["day_night_phase"] = dayNight.phase.rawValue
        r["audio_reactive"] = audio.status.text
        r["screens"] = NSScreen.screens.map { "\($0.localizedName) \($0.pixelSize)" }
        return r
    }
}
