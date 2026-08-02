//
//  TriageMetrics.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import CoreGraphics

/// Geometry that only the swipe deck needs. Shared values (screen padding,
/// thumbnail sizing) come from ``Spacing``; colours come from ``Palette``.
enum TriageMetrics {
    /// Tighter than the app default: the deck has to fit a card, hints, and
    /// controls between the navigation bar and the home indicator.
    static let sectionSpacing: CGFloat = 16
    /// Larger than a standard card — it is the full-bleed hero of the screen.
    static let cardCornerRadius: CGFloat = 32
    /// How far a card must travel before the swipe commits to a verdict.
    static let decisionThreshold: CGFloat = 120
    /// The card tracks the finger from the first touch, so a stationary press
    /// still opens a drag. Travel under this reads as a tap, not a swipe.
    static let tapSlop: CGFloat = 10
    /// How long the fly-off plays before the deck advances. Gestures are ignored
    /// for this window, so it stays only as long as the card needs to clear the
    /// screen edge.
    static let flyOffDuration = Duration.milliseconds(200)

    static let actionButtonSize: CGFloat = 64
    static let actionButtonHaloPadding: CGFloat = 12
    static let undoButtonHeight: CGFloat = 40
    static let undoButtonHorizontalPadding: CGFloat = 12

    static let hintArrowSize: CGFloat = 24
    static let hintArrowSpacing: CGFloat = 10
    static let hintTextWidth: CGFloat = 72
    static let hintGroupSpacing: CGFloat = 12
    static let hintDividerHeight: CGFloat = 32

    static let imageModeTransitionDuration = 0.18
}
