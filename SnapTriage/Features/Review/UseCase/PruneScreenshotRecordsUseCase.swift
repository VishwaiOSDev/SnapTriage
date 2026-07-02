//
//  PruneScreenshotRecordsUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 02/07/26.
//

import Foundation

/// Drops every stored record for screenshots that were just deleted from the
/// library, so the persisted stores don't accumulate dead asset ids.
struct PruneScreenshotRecordsUseCase {

    let decisions: TriageDecisionStore
    let categories: CategoryStore
    let ocr: OCRStore

    func execute(_ ids: [Screenshot.ID]) async {
        guard !ids.isEmpty else { return }
        decisions.remove(ids)
        await categories.remove(ids)
        await ocr.remove(ids)
    }
}
