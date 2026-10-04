// Per-display wallpaper assignments.
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import IOKit.ps
import ServiceManagement
import Security
import UniformTypeIdentifiers
import ImageIO

struct DisplaysView: View {
    @EnvironmentObject var engine: WallpaperEngine
    @EnvironmentObject var store: Store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(title: "Displays", subtitle: "Each display gets its own looping player. New monitors follow the “All Displays” wallpaper automatically.")
                HStack {
                    Button { engine.togglePause() } label: {
                        Label(engine.state.userPaused ? "Resume All" : "Pause All", systemImage: engine.state.userPaused ? "play.fill" : "pause.fill")
                    }
                    Button { store.next() } label: { Label("Random from Library", systemImage: "shuffle") }
                    if let r = engine.pauseReason { Text("Paused: \(r)").foregroundStyle(.orange) }
                }
                let _ = engine.tick
                ForEach(NSScreen.screens, id: \.stableKey) { s in
                    let a = engine.assignment(for: s)
                    let lib = a.flatMap { store.libraryItem($0.itemID) }
                    HStack(spacing: 16) {
                        Color.clear.frame(width: 220, height: 124)
                            .overlay(RemoteImage(url: lib?.thumbURL, localPath: lib?.thumbPath))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.localizedName).font(.headline)
                            Text("\(s.pixelSize) · \(s == NSScreen.main ? "main display" : "secondary")").font(.caption).foregroundStyle(.secondary)
                            Text(a?.title ?? "No wallpaper from this app").font(.callout.weight(.medium))
                            if let a {
                                let paused = engine.screenPaused(s)
                                Label(a.kind == .image ? "Still image" : (paused.map { "Paused — \($0)" } ?? "Playing live"),
                                      systemImage: a.kind == .image ? "photo" : (paused == nil ? "play.circle.fill" : "pause.circle"))
                                    .foregroundStyle(a.kind == .image ? Color.secondary : (paused == nil ? accent : .orange)).font(.caption)
                                Text(engine.state.perScreen[s.stableKey] != nil ? "Set for this display only" : "Following “All Displays”")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if a != nil { Button("Clear") { engine.clear(screenKey: s.stableKey) } }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                }
            }.padding(24)
        }
    }
}
