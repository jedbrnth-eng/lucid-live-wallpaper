// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Playlist playback, as pure logic: when the next change is due (every N minutes, or at listed times of day),
// shuffle without repeats, keeping position when the playlist is edited, and saved runs (one per display, or "*"
// for all displays) so playback resumes where it was after a relaunch. Clocks and randomness are injected.
import Foundation

/// One playlist playing on one scope (a display key, or "*" for all displays).
struct PlaylistRun: Codable, Equatable {
    var playlistID: String
    var order: [String]      // item ids in play order (shuffled once per round when shuffle is on)
    var position: Int
    var changedAt: Date

    init<R: RandomNumberGenerator>(playlistID: String, ids: [String], shuffle: Bool, now: Date, rng: inout R) {
        self.playlistID = playlistID
        order = shuffle ? ids.shuffled(using: &rng) : ids
        position = 0
        changedAt = now
    }
    init(playlistID: String, ids: [String], shuffle: Bool, now: Date) {
        var g = SystemRandomNumberGenerator()
        self.init(playlistID: playlistID, ids: ids, shuffle: shuffle, now: now, rng: &g)
    }

    var current: String? { order.indices.contains(position) ? order[position] : nil }

    /// A position outside the saved order (hand-edited or damaged playback.json) restarts at the first item.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playlistID = try c.decode(String.self, forKey: .playlistID)
        order = try c.decode([String].self, forKey: .order)
        changedAt = try c.decode(Date.self, forKey: .changedAt)
        let p = try c.decode(Int.self, forKey: .position)
        position = order.indices.contains(p) ? p : 0
    }

    /// Next item. A new round starts when every item has been shown; with shuffle the new round never starts
    /// with the item that is on screen now.
    mutating func advance<R: RandomNumberGenerator>(ids: [String], shuffle: Bool, now: Date, rng: inout R) {
        changedAt = now
        position += 1
        guard position >= order.count else { return }
        let last = current ?? order.last
        order = shuffle ? ids.shuffled(using: &rng) : ids
        if shuffle, order.count > 1, order.first == last, let i = order.indices.dropFirst().randomElement(using: &rng) { order.swapAt(0, i) }
        position = 0
    }

    mutating func back() {
        guard !order.isEmpty else { return }
        position = position > 0 ? position - 1 : order.count - 1
    }

    /// The playlist was edited while playing: keep what's on screen, drop removed items, add new ones.
    mutating func reconcile<R: RandomNumberGenerator>(ids: [String], shuffle: Bool, rng: inout R) {
        let keep = Set(ids)
        let cur = current
        // If the current item was removed, carry on with the next surviving item after it.
        let successor = cur.flatMap { c in keep.contains(c) ? c : nil }
            ?? (order.indices.contains(position) ? order[position...].first { keep.contains($0) } : nil)
        var next = order.filter { keep.contains($0) }
        let added = ids.filter { !Set(next).contains($0) }
        next += shuffle ? added.shuffled(using: &rng) : added
        order = next
        position = successor.flatMap { order.firstIndex(of: $0) } ?? 0
    }
}

enum PlaylistScheduler {
    /// Valid minutes-after-midnight, unique and sorted.
    static func sanitize(_ times: [Int]?) -> [Int] { Array(Set((times ?? []).filter { (0..<1440).contains($0) })).sorted() }

    /// When the playlist should change next: at the next listed time of day (wall clock in `timeZone`), else
    /// `minutes` after the last change; nil = never (manual only).
    static func nextFire(lastChange: Date, minutes: Int, times: [Int]?, timeZone: TimeZone) -> Date? {
        let t = sanitize(times)
        if !t.isEmpty {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
            let day0 = cal.startOfDay(for: lastChange)
            for offset in 0...2 {
                guard let day = cal.date(byAdding: .day, value: offset, to: day0) else { continue }
                for m in t {
                    if let d = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day), d > lastChange { return d }
                }
            }
        }
        return minutes > 0 ? lastChange.addingTimeInterval(Double(minutes) * 60) : nil
    }

    static func isDue(_ r: PlaylistRun, minutes: Int, times: [Int]?, timeZone: TimeZone, now: Date) -> Bool {
        guard now >= r.changedAt, let f = nextFire(lastChange: r.changedAt, minutes: minutes, times: times, timeZone: timeZone) else { return false }
        return now >= f
    }

    /// "07:00, 18:30" -> [420, 1110]. Invalid entries are skipped; input and output are bounded.
    static func parseTimes(_ s: String) -> [Int] {
        let parts = String(s.prefix(2000)).split { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" }.prefix(48)
        let mins: [Int] = parts.compactMap { p in
            let hm = p.split(separator: ":")
            guard hm.count == 2, (1...2).contains(hm[0].count), hm[1].count == 2,
                  let h = Int(hm[0]), let m = Int(hm[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
            return h * 60 + m
        }
        return sanitize(mins)
    }
    static func formatTimes(_ t: [Int]?) -> String { sanitize(t).map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }.joined(separator: ", ") }
}

/// Saved as playback.json. Each run decodes on its own, so one damaged entry never loses the others.
struct PlaybackState: Codable, Equatable {
    var runs: [String: PlaylistRun] = [:]
    static func decode(_ d: Data) -> PlaybackState {
        struct Lenient: Decodable { var runs: LossyDictionary<PlaylistRun>? }
        return PlaybackState(runs: ((try? JSONDecoder().decode(Lenient.self, from: d))?.runs?.values) ?? [:])
    }
}
