//
//  LimitedAccessBanner.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import SwiftUI

/// Says out loud that the numbers on screen describe a hand-picked subset.
///
/// Limited access reads exactly like full access to the app — the fetch just
/// returns fewer assets — so "180 MB reclaimable" over twenty selected photos is
/// indistinguishable from the same figure over a whole library. Without this the
/// user has no way to know which one they are looking at, and no way to widen it.
struct LimitedAccessBanner: View {
    let onAddPhotos: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.Access.limitedTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                Text(Strings.Access.limitedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onAddPhotos) {
                    Text(Strings.Access.limitedAction)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#if DEBUG
private struct LimitedAccessBanner_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            LimitedAccessBanner {}
                .padding()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
