// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Day & Night at a glance: the four wallpapers in the order the day plays them, when each starts today, and a
// thin bar of the day's light drawn from the colours measured in each picture.
import SwiftUI

struct SunStrip: View {
    struct Slot: Identifiable {
        let part: DayPart
        var title: String?
        /// A picture on this Mac (SunPicker.posterPath); the strip never loads anything from the web.
        var posterPath: String?
        var starts: Date?
        var tint: Color?
        var isNow = false
        var id: String { part.rawValue }
    }
    let slots: [Slot]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(slots) { tile($0) }
            }
            Capsule()
                .fill(LinearGradient(colors: slots.map { $0.tint ?? Theme.faint.opacity(0.5) }, startPoint: .leading, endPoint: .trailing))
                .frame(height: 3)
                .accessibilityHidden(true)
        }
    }

    private func tile(_ s: Slot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(Self.name(s.part).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.1)
                    .foregroundStyle(s.isNow ? Theme.cyan : Theme.muted)
                Spacer(minLength: 2)
                if let t = s.starts {
                    Text(t, format: .dateTime.hour().minute())
                        .font(.system(size: 10, design: .monospaced)).monospacedDigit().foregroundStyle(Theme.faint)
                }
            }
            ZStack {
                if s.title != nil {
                    RemoteImage(url: nil, localPath: s.posterPath)
                } else {
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    Image(systemName: s.part.symbol).foregroundStyle(Theme.faint)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(s.isNow ? Theme.cyan.opacity(0.8) : Theme.line, lineWidth: 1))
            Text(s.title ?? Self.fallback(s.part))
                .font(.caption).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(s.title == nil ? Theme.faint : Theme.ink)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.name(s.part)): \(s.title ?? Self.fallback(s.part))\(s.isNow ? ", now" : "")")
    }

    static func name(_ p: DayPart) -> String {
        switch p { case .dawn: return "Dawn"; case .day: return "Day"; case .dusk: return "Dusk"; case .night: return "Night" }
    }
    /// What an empty dawn or dusk shows (DayNightRule falls back to day/night).
    static func fallback(_ p: DayPart) -> String {
        switch p { case .dawn: return "Night, then Day"; case .dusk: return "Day, then Night"; case .day, .night: return "Choose…" }
    }
}
