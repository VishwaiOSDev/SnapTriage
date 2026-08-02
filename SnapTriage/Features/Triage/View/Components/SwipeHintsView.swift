//
//  SwipeHintsView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

/// Teaches the two swipe directions, colour-coded to match the verdict buttons
/// directly below them.
struct SwipeHintsView: View {
    var body: some View {
        HStack(spacing: 0) {
            hintLabel(
                text: Strings.Triage.swipeRightHint,
                arrow: "arrow.right",
                color: Palette.controlKeep,
                arrowLeading: true
            )
            Spacer(minLength: TriageMetrics.hintGroupSpacing)
            divider
            Spacer(minLength: TriageMetrics.hintGroupSpacing)
            hintLabel(
                text: Strings.Triage.swipeLeftHint,
                arrow: "arrow.left",
                color: Palette.controlDelete,
                arrowLeading: false
            )
        }
    }

    private func hintLabel(text: String, arrow: String, color: Color, arrowLeading: Bool) -> some View {
        HStack(spacing: TriageMetrics.hintArrowSpacing) {
            if arrowLeading { glossyArrow(arrow, color: color) }
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.72), color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: TriageMetrics.hintTextWidth, alignment: .leading)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if !arrowLeading { glossyArrow(arrow, color: color) }
        }
    }

    private func glossyArrow(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: TriageMetrics.hintArrowSize, weight: .light))
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.72), color, color.opacity(0.58)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: color.opacity(0.45), radius: 5)
    }

    private var divider: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.28), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: TriageMetrics.hintDividerHeight)
    }
}
