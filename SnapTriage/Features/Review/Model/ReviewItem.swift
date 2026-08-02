//
//  ReviewItem.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation

/// A screenshot presented in the Review grid for a final check. Pure value type;
/// selection state lives in the ViewModel so the same item can be toggled
/// without rebuilding the list.
struct ReviewItem: Identifiable, Equatable, Sendable {

    /// Why the screenshot is on this screen. The distinction is a safety
    /// boundary, not a label: only a verdict the user actually gave may arrive
    /// pre-selected for deletion. A classifier guess has to be opted into.
    enum Source: Equatable, Sendable {
        /// The user swiped this card left during a triage pass.
        case userMarked
        /// The classifier judged it `safeToDelete`; the user has not seen it.
        case suggested
    }

    let id: Screenshot.ID
    let category: ScreenshotCategory
    let byteSize: Int
    let source: Source

    init(
        id: Screenshot.ID,
        category: ScreenshotCategory,
        byteSize: Int,
        source: Source = .userMarked
    ) {
        self.id = id
        self.category = category
        self.byteSize = byteSize
        self.source = source
    }
}
