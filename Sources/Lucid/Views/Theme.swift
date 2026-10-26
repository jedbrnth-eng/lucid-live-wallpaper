// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// The look shared with the website (lucid-wallpaper.vercel.app): deep indigo night, soft ink, cyan/pink/violet light.
import SwiftUI

enum Theme {
    private static func rgb(_ hex: UInt32, _ a: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: a)
    }
    static let bg = rgb(0x05061C)
    static let bg2 = rgb(0x0A0B2E)
    static let ink = rgb(0xF5F1FF)
    static let muted = rgb(0xA7A2D4)
    static let faint = rgb(0x6C67A3)
    static let cyan = rgb(0x6FF3FF)
    static let pink = rgb(0xFF5FBF)
    static let violet = rgb(0x7C5CFF)
    static let line = Color(red: 190 / 255, green: 170 / 255, blue: 1, opacity: 0.14)
    static let surface = Color(red: 190 / 255, green: 170 / 255, blue: 1, opacity: 0.06)

    /// Corner radii: cards and panels, small controls.
    static let radius: CGFloat = 14
    static let radiusSmall: CGFloat = 8
    /// Page padding and gaps.
    static let pad: CGFloat = 28
    static let gap: CGFloat = 16

    static let glow = LinearGradient(colors: [pink, violet, cyan], startPoint: .leading, endPoint: .trailing)

    /// The page background: the site's night gradient with a faint violet glow at the top.
    static var backdrop: some View {
        ZStack {
            LinearGradient(colors: [bg2, bg], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [violet.opacity(0.22), .clear], center: .init(x: 0.75, y: 0), startRadius: 0, endRadius: 520)
        }
    }
}

/// The site's pill buttons: primary = light ink with dark text, secondary = outlined glass.
struct PillButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, primary: primary)
    }
    private struct PillBody: View {
        let configuration: Configuration
        let primary: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16).padding(.vertical, 8)
                .foregroundStyle(primary ? Theme.bg : Theme.ink)
                .background(Capsule().fill(primary ? Theme.ink : (hover ? Theme.surface.opacity(2) : Theme.surface)))
                .overlay(Capsule().stroke(primary ? Color.clear : (hover ? Theme.muted.opacity(0.6) : Theme.line), lineWidth: 1))
                .shadow(color: primary ? Theme.violet.opacity(hover ? 0.55 : 0.3) : .clear, radius: hover ? 14 : 8)
                .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.15), value: hover)
                .onHover { hover = $0 }
                .contentShape(Capsule())
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillPrimary: PillButtonStyle { PillButtonStyle(primary: true) }
}

/// A small mono caps label like the site's version pill.
struct MonoPill: View {
    let text: String
    var dot: Color? = Theme.cyan
    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            Text(text).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.ink.opacity(0.9))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().stroke(Theme.line))
    }
}
