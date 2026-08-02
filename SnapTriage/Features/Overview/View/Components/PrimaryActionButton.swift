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
        .buttonStyle(GlossyActionButtonStyle(shape: Capsule()))
    }
}
