//
//  LiquidGlass.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import SwiftUI

/// One surface treatment for every glass element. On iOS 26 it's the real
/// `glassEffect` — it samples, reflects, and refracts whatever sits behind and
/// beside it. Older systems fall back to a translucent material + hairline border.
private struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            content
                .background(tint?.opacity(0.2) ?? Palette.surfaceFill, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(
                        tint?.opacity(0.4) ?? Palette.cardStroke,
                        lineWidth: 1
                    )
                }
        }
    }
}

extension View {
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint))
    }

    /// Lets neighboring glass elements sample and blend one another (iOS 26+).
    @ViewBuilder
    func glassContainer(spacing: CGFloat = Spacing.sectionSpacing) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}
