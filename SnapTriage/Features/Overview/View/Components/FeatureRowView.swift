//
//  FeatureRowView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import SwiftUI

/// One row in the "what this app does" list.
struct FeatureRowView: View {
    let feature: FeatureHighlight

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34)
                .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
