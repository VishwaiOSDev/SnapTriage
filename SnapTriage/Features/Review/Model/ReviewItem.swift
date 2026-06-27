//
//  ReviewItem.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation

/// A screenshot the classifier marked `safeToDelete`, presented in the Review
/// grid for a final check. Pure value type; selection state lives in the
/// ViewModel so the same item can be toggled without rebuilding the list.
struct ReviewItem: Identifiable, Equatable, Sendable {
    let id: Screenshot.ID
    let category: ScreenshotCategory
    let byteSize: Int
}
