// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Calls back on the main queue when entries are added to, removed from or renamed in any of the folders, so a scan
// runs when something changed instead of every few seconds. A burst of events (a copy, a save) is one call after
// `debounce`. Only the folders' own entries are watched: a file growing inside one sends nothing, so callers look
// again at files that are still being written (ImportPolicy.recheckDelay). Foundation and Dispatch only.
import Foundation

final class DirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private var pending = false

    init(_ dirs: [URL], debounce: TimeInterval = 0.5, onChange: @escaping () -> Void) {
        self.debounce = debounce
        self.onChange = onChange
        for d in dirs {
            let fd = open(d.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link], queue: .main)
            s.setEventHandler { [weak self] in self?.changed() }
            s.setCancelHandler { close(fd) }
            s.resume()
            sources.append(s)
        }
    }

    deinit { sources.forEach { $0.cancel() } }

    private func changed() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce) { [weak self] in
            guard let self else { return }
            self.pending = false
            self.onChange()
        }
    }
}
