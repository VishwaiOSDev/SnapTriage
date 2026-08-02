//
//  PrimaryActionButton.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import SwiftUI

/// The screen's single call to action. Solid and saturated so it reads as the
/// one thing to press among the surrounding glass.
struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.94))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 15)
                .frame(minHeight: 56)
                .contentShape(Capsule())
        }
        .buttonStyle(PrimaryActionButtonStyle())
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Capsule()
                    .fill(Self.fill)
                    .overlay {
                        Capsule().fill(Self.sheen)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Self.rim, lineWidth: 1)
                    }
            }
            .shadow(
                color: Self.glow.opacity(configuration.isPressed ? 0.06 : 0.10),
                radius: configuration.isPressed ? 5 : 8,
                y: 2
            )
            .shadow(color: .black.opacity(0.30), radius: 4, y: 3)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }

    // Sampled from the Figma primary action reference. A diagonal transition
    // preserves its brighter leading edge and slightly deeper trailing edge.
    private static let fill = LinearGradient(
        colors: [
            Palette.accent,
            Color(red: 0.13, green: 0.41, blue: 0.87)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    private static let sheen = LinearGradient(
        colors: [.white.opacity(0.025), .clear],
        startPoint: .top,
        endPoint: .center
    )
    private static let rim = LinearGradient(
        colors: [
            Color(red: 0.31, green: 0.61, blue: 1.0).opacity(0.9),
            Color(red: 0.17, green: 0.51, blue: 0.97).opacity(0.7)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    private static let glow = Color(red: 0.08, green: 0.38, blue: 0.95)
}
