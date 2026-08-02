//
//  Spacing.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import CoreGraphics

/// Shared layout constants. Feature-specific geometry (the triage deck's swipe
/// threshold, its oversized card radius) stays with that feature.
enum Spacing {

    // MARK: Screen

    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 20

    // MARK: Cards

    static let cardCornerRadius: CGFloat = 28
    static let cardPadding: CGFloat = 20

    // MARK: Thumbnails

    static let gridSpacing: CGFloat = 8
    static let thumbnailMinWidth: CGFloat = 100
    static let thumbnailCornerRadius: CGFloat = 10
    static let thumbnailAspectRatio: CGFloat = 0.66
}
