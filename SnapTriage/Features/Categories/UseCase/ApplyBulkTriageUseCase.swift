//
//  ApplyBulkTriageUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import Foundation

/// Records one verdict across a whole category.
///
/// Writes to the same decision store a swipe does, so a bulk verdict is a
/// first-class triage decision: the deck stops offering those cards, and marked
/// screenshots land in Review as user-marked, behind the same confirmation as
/// anything else. Nothing here touches the photo library.
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
