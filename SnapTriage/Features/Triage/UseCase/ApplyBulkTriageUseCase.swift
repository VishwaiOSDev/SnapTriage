//
//  ApplyBulkTriageUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import Foundation

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

/// Records one verdict across a whole category.
///
/// Writes to the same decision store a swipe does, so a bulk verdict is a
/// first-class triage decision: the deck stops offering those cards, and marked
/// screenshots land in Review as user-marked, behind the same confirmation as
/// anything else. Nothing here touches the photo library.
///
/// Lives with the other triage decision use cases because that is what it
/// writes. Its caller is the category-scoped Review screen, which is the only
/// place a bulk verdict can be given — with the screenshots on screen.
struct ApplyBulkTriageUseCase {

    let store: TriageDecisionStore

    /// Returns a receipt carrying the prior verdicts, so the caller can offer a
    /// real undo rather than an approximate one.
    func execute(
        _ decision: TriageDecision,
        for category: ScreenshotCategory,
        ids: [Screenshot.ID]
    ) -> BulkTriageReceipt {
        var previous: [Screenshot.ID: TriageDecision] = [:]
        for id in ids {
            if let existing = store.decision(for: id) {
                previous[id] = existing
            }
            store.save(decision, for: id)
        }
        return BulkTriageReceipt(
            category: category,
            decision: decision,
            ids: ids,
            previous: previous
        )
    }
}

/// Puts a bulk verdict back exactly as it was: ids that had no verdict return to
/// having none, ids that carried one get it back.
struct RevertBulkTriageUseCase {

    let store: TriageDecisionStore

    func execute(_ receipt: BulkTriageReceipt) {
        store.remove(receipt.ids)
        for (id, decision) in receipt.previous {
            store.save(decision, for: id)
        }
    }
}
