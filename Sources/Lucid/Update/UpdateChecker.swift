// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Off by default. When on: one anonymous HTTPS GET to api.github.com per day (no ID, no telemetry). If a newer
// release exists, Settings shows a link to its GitHub page. Nothing is downloaded or installed automatically.
import Foundation

@MainActor final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    @Published private(set) var available: ReleaseInfo?
    @Published private(set) var status = ""
    private var timer: Timer?
    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 20
        c.httpAdditionalHeaders = ["User-Agent": Net.ua, "Accept": "application/vnd.github+json"]
        return URLSession(configuration: c)
    }()

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkIfDue() } }
        checkIfDue()
    }

    func checkIfDue(force: Bool = false) {
        guard force ? Pref.updateCheck : UpdateCheck.shouldCheck(enabled: Pref.updateCheck, last: Pref.lastUpdateCheck, now: Date()),
              let url = UpdateCheck.apiURL else { return }
        Pref.lastUpdateCheck = Date()
        status = "Checking…"
        Task {
            do {
                let (d, resp) = try await Self.session.data(from: url)
                guard let h = resp as? HTTPURLResponse, h.statusCode == 200, h.url?.host == "api.github.com",
                      d.count <= UpdateCheck.maxBytes, let r = UpdateCheck.parse(d) else { throw URLError(.cannotParseResponse) }
                available = UpdateCheck.isNewer(r.version, than: current) ? r : nil
                status = available.map { "Lucid \($0.version) is available" } ?? "You have the latest version (\(current))"
            } catch { status = "Couldn't check right now" }
        }
    }
}
