// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Per-wallpaper display options (fit / fill / stretch, crop focus, playback speed), shown in a library item's detail.
import SwiftUI

struct WallpaperOptionsRow: View {
    let item: WallItem
    @EnvironmentObject var store: Store

    private enum Focus: String, CaseIterable { case center = "Center", top = "Top", bottom = "Bottom", left = "Left", right = "Right"
        var xy: (Double?, Double?) {
            switch self {
            case .center: return (nil, nil)
            case .top: return (nil, 0)
            case .bottom: return (nil, 1)
            case .left: return (0, nil)
            case .right: return (1, nil)
            }
        }
        static func from(_ o: WallpaperOptions) -> Focus {
            switch (o.focusX, o.focusY) {
            case (_, .some(let y)) where y < 0.5: return .top
            case (_, .some(let y)) where y > 0.5: return .bottom
            case (.some(let x), _) where x < 0.5: return .left
            case (.some(let x), _) where x > 0.5: return .right
            default: return .center
            }
        }
    }

    private var options: WallpaperOptions { store.libraryItem(item.id)?.options ?? WallpaperOptions() }
    private func set(_ change: (inout WallpaperOptions) -> Void) { var o = options; change(&o); store.setOptions(item, o) }

    var body: some View {
        HStack(spacing: 14) {
            Picker("Fit", selection: Binding(get: { options.fit?.rawValue ?? "" }, set: { v in set { $0.fit = FitMode(rawValue: v) } })) {
                Text("App default").tag(""); Text("Fill (crop)").tag(FitMode.fill.rawValue)
                Text("Fit (letterbox)").tag(FitMode.fit.rawValue); Text("Stretch").tag(FitMode.stretch.rawValue)
            }.frame(maxWidth: 210).accessibilityLabel("Fit for this wallpaper")
            Picker("Crop focus", selection: Binding(get: { Focus.from(options) }, set: { f in set { $0.focusX = f.xy.0; $0.focusY = f.xy.1 } })) {
                ForEach(Focus.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.frame(maxWidth: 190).disabled(options.effectiveFit(defaultFill: Pref.fillScreen) != .fill)
                .accessibilityLabel("Which part stays visible when the wallpaper is cropped")
            if item.kind == .video {
                Picker("Speed", selection: Binding(get: { options.speed ?? 0 }, set: { v in set { $0.speed = v == 0 ? nil : v } })) {
                    Text("App default").tag(0.0); ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { Text(String(format: "%g×", $0)).tag($0) }
                }.frame(maxWidth: 170).accessibilityLabel("Playback speed for this wallpaper")
            }
            if item.referenced == true {
                Label("Used in place", systemImage: "link").font(.caption).foregroundStyle(.secondary)
                    .help("Lucid plays this file where it is and never deletes it. Moving or renaming it removes it from Lucid.")
            }
            Spacer()
        }
        .font(.callout)
    }
}
