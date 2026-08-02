//
//  GlossyActionButton.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 02/08/26.
//

import SwiftUI

/// The colour set of a glossy action button: a diagonal fill, the rim that
/// keeps its edge crisp on a dark background, and the glow it casts.
struct ActionButtonTone {
    let fill: [Color]
    let rim: [Color]
    let glow: Color

    /// Sampled from the Figma primary action reference. A diagonal transition
    /// preserves its brighter leading edge and slightly deeper trailing edge.
    static let primary = ActionButtonTone(
        fill: [
            Palette.accent,
            Color(red: 0.13, green: 0.41, blue: 0.87)
        ],
        rim: [
            Color(red: 0.31, green: 0.61, blue: 1.0).opacity(0.9),
            Color(red: 0.17, green: 0.51, blue: 0.97).opacity(0.7)
        ],
        glow: Color(red: 0.08, green: 0.38, blue: 0.95)
    )

    /// The same treatment carried over to the destructive action, so "delete"
    /// reads as the twin of "start" rather than a differently-built control.
    static let destructive = ActionButtonTone(
        fill: [
            Color(red: 0.91, green: 0.25, blue: 0.31),
            Color(red: 0.72, green: 0.11, blue: 0.19)
        ],
        rim: [
            Color(red: 1.0, green: 0.45, blue: 0.47).opacity(0.9),
            Color(red: 0.90, green: 0.24, blue: 0.30).opacity(0.7)
        ],
        glow: Color(red: 0.93, green: 0.19, blue: 0.26)
    )
}

/// The house style for a call to action: solid and saturated so it reads as the
/// one thing to press among the surrounding glass. Shape and tone vary; the
/// gloss, rim, glow, and press response do not.
struct GlossyActionButtonStyle<Surface: InsettableShape>: ButtonStyle {
    var tone: ActionButtonTone = .primary
    var shape: Surface

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                shape
                    .fill(fill)
                    .overlay { shape.fill(Self.sheen) }
                    .overlay { shape.strokeBorder(rim, lineWidth: 1) }
            }
            .shadow(
                color: tone.glow.opacity(configuration.isPressed ? 0.06 : 0.10),
                radius: configuration.isPressed ? 5 : 8,
                y: 2
            )
            .shadow(color: .black.opacity(0.30), radius: 4, y: 3)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }

    private var fill: LinearGradient {
        LinearGradient(colors: tone.fill, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var rim: LinearGradient {
        LinearGradient(colors: tone.rim, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static var sheen: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.025), .clear], startPoint: .top, endPoint: .center)
    }
}

#if DEBUG
private struct GlossyActionButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Button {} label: {
                    Text("Start Triage")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(GlossyActionButtonStyle(shape: Capsule()))

                Button {} label: {
                    Text("Delete 1,059 screenshots")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(
                    GlossyActionButtonStyle(
                        tone: .destructive,
                        shape: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                )
            }
            .padding(Spacing.screenPadding)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
