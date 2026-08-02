//
//  UndoButton.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

/// Compact on-demand utility: violet identifies a reversible action without
/// borrowing the blue Keep or red Delete semantics of the primary controls.
struct UndoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))
                Text(Strings.Triage.undo)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, TriageMetrics.undoButtonHorizontalPadding)
            .frame(height: TriageMetrics.undoButtonHeight)
            .liquidGlass(in: Capsule(), tint: Palette.controlUndo.opacity(0.5))
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.38),
                                Palette.controlUndo.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(
                color: Palette.controlUndo.opacity(0.32),
                radius: 10,
                y: 4
            )
            // The visible capsule stays compact while its effective touch
            // target meets the 44pt minimum.
            .padding(.vertical, 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.Triage.undo)
    }
}
