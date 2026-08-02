//
//  GlassCard.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import SwiftUI

/// A rounded glass surface. The default card shape for grouped content.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Spacing.cardCornerRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
