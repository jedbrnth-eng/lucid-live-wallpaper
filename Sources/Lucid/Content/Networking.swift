// Small HTTP helpers shared by the content providers.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

// MARK: - Networking

enum NetError: LocalizedError {
    case http(Int), badData, noKey
    var errorDescription: String? {
        switch self {
        case .http(let c): return c == 401 || c == 403 ? "The service rejected the API key (HTTP \(c))." : c == 429 ? "Rate limited by the service — try again in a minute." : "Server error (HTTP \(c))."
        case .badData: return "Unexpected response from the service."
        case .noKey: return "API key needed."
        }
    }
}

enum Net {
    static let ua = "Lucid/1.0 (macOS live wallpaper app; +https://github.com/jedbrnth-eng/lucid-live-wallpaper)"
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["User-Agent": ua]
        c.timeoutIntervalForRequest = 30
        c.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        return URLSession(configuration: c)
    }()
    static func json(_ url: URL, headers: [String: String] = [:]) async throws -> [String: Any] {
        var r = URLRequest(url: url)
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        let (d, resp) = try await session.data(for: r)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw NetError.http(h.statusCode) }
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw NetError.badData }
        return j
    }
    static func url(_ base: String, _ q: [String: String]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = q.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url!
    }
}
