//
//  CategoryGroup.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import Foundation

/// Every screenshot the classifier put in one bucket that the user has not yet
/// ruled on. This is the unit a bulk verdict applies to.
struct CategoryGroup: Identifiable, Equatable, Sendable {
    let category: ScreenshotCategory
    /// The retention leaning shared by the group, used to colour the row and to
    /// order the list — it does not decide anything on the user's behalf.
    let disposition: ScreenshotDisposition
    let ids: [Screenshot.ID]
    let byteSize: Int

    var id: ScreenshotCategory { category }
    var count: Int { ids.count }
}

/// What the category screen knows about the library right now.
struct CategoryBreakdown: Equatable, Sendable {
    var groups: [CategoryGroup] = []
    /// Screenshots with no verdict that the pipeline has not resolved yet. They
    /// cannot be grouped, and saying so is better than quietly omitting them.
    var unclassifiedCount = 0
    /// Screenshots that already carry a swipe verdict, bulk or otherwise.
    var decidedCount = 0

    var undecidedCount: Int {
        groups.reduce(unclassifiedCount) { $0 + $1.count }
    }

    var isEmpty: Bool { groups.isEmpty && unclassifiedCount == 0 }

    static let empty = CategoryBreakdown()
}

/// A bulk verdict that has been applied, kept so it can be taken back. Bulk
/// actions touch hundreds of screenshots at once, which is exactly when a
/// mis-tap is expensive and an undo is cheap.
struct BulkTriageReceipt: Equatable, Sendable {
    let category: ScreenshotCategory
    let decision: TriageDecision
    let ids: [Screenshot.ID]
    /// Verdicts these screenshots carried beforehand, so undo restores the prior
    /// state rather than merely clearing it.
    let previous: [Screenshot.ID: TriageDecision]

    var count: Int { ids.count }
}
