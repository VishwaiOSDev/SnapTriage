//
//  HeroMetricText.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import SwiftUI

/// Large luminous metric readout, e.g. the Overview "3.2 GB".
/// iOS 26+: glass foreground effects applied directly to the text glyphs.
/// Older OS: gradient + glow + specular sheen fallback.
struct HeroMetricText: View {
    private let text: String
    private let size: CGFloat

    init(_ text: String = "3.2 GB", size: CGFloat = 84) {
        self.text = text
        self.size = size
    }

    private var font: Font { .system(size: size, weight: .bold, design: .rounded) }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Self.gradient)
            .shadow(color: Self.glow, radius: size * 0.22)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 2)
            .overlay {
                // Top-left specular sheen added with light blend mode.
                Text(text)
                    .font(font)
                    .foregroundStyle(Self.sheen)
                    .blendMode(.plusLighter)
                    .mask(Text(text).font(font))
            }
            .liquidGlassGlyphs(text: text, font: font)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
            .accessibilityLabel(text)
    }

    // MARK: - Palette

    private static let brightBlue = Color(red: 0.31, green: 0.58, blue: 1.0)
    private static let mainBlue   = Color(red: 0.13, green: 0.43, blue: 1.0)
    private static let deepBlue   = Color(red: 0.05, green: 0.20, blue: 0.55)
    private static let glow       = mainBlue.opacity(0.30)

    private static let gradient = LinearGradient(
        colors: [brightBlue, mainBlue, deepBlue],
        startPoint: .leading,
        endPoint: .trailing
    )

    private static let sheen = LinearGradient(
        colors: [brightBlue.opacity(0.25), .blue.opacity(0.05), .clear],
        startPoint: .topLeading,
        endPoint: UnitPoint(x: 0.6, y: 0.55)
    )
}

// MARK: - Liquid Glass backport

private extension View {
    /// Simulates a Liquid Glass material inside the glyph shapes: a translucent
    /// highlight rim plus a soft inner sheen, masked to the text. The system
    /// `glassEffect` material cannot be clipped to arbitrary glyph masks, so the
    /// look is approximated with layered gradients that read as glass.
    func liquidGlassGlyphs(text: String, font: Font) -> some View {
        overlay {
            ZStack {
                // Soft top-down sheen — the "lit" face of the glass.
                LinearGradient(
                    colors: [.white.opacity(0.25), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                // Crisp specular highlight on the upper-left edge, tinted blue
                // so the glyphs stay blue instead of washing out to white.
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.78, blue: 1.0).opacity(0.6), .clear],
                    startPoint: .topLeading,
                    endPoint: UnitPoint(x: 0.45, y: 0.4)
                )
                .blendMode(.softLight)
            }
            .mask(Text(text).font(font))
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea()
        VStack(spacing: 0) {
            HeroMetricText("3.2 GB")
            HeroMetricText("18.4 GB", size: 64)
            HeroMetricText("512 MB", size: 48)
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
