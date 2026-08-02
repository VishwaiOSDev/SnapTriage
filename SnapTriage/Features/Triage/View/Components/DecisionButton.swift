//
//  DecisionButton.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

/// A primary verdict control — the tap equivalent of swiping the top card.
struct DecisionButton: View {
    let systemImage: String
    let color: Color
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: TriageMetrics.actionButtonSize, height: TriageMetrics.actionButtonSize)
                .background(
                    LinearGradient(
                        colors: [color.opacity(0.72), color, color.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.5), color.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.25
                        )
                }
                .shadow(color: color.opacity(0.42), radius: 14, y: 5)
                .padding(TriageMetrics.actionButtonHaloPadding)
                .background(.ultraThinMaterial, in: Circle())
                .background(Color.white.opacity(0.025), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.035), color.opacity(0.055), .black.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                }
                .shadow(color: .black.opacity(0.38), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
