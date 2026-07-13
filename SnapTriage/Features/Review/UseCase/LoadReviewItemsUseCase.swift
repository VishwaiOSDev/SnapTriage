//
//  LoadReviewItemsUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation

/// Produces the deletion set for the Review screen. It drives the (cache-first)
/// classification pipeline to completion so every screenshot has a classification
/// in the shared store, then folds in the user's triage swipes: a swipe always
/// overrides the classifier, and screenshots without a verdict are included only
/// when the classifier's retention judgement is `safeToDelete`. Needs-review and
/// useful screenshots are never pre-selected for deletion — the user decides.
/// When Overview has already classified, this is effectively free — every
/// screenshot is a cache hit.
struct LoadReviewItemsUseCase {

    let loadScreenshots: LoadScreenshotsUseCase
    let classifyLibrary: ClassifyLibraryUseCase
    let store: CategoryStore
    let decisions: TriageDecisionStore

    func execute() async throws -> [ReviewItem] {
        let screenshots = try await loadScreenshots.execute()
        guard !screenshots.isEmpty else { return [] }

        // Ensure a category exists for each screenshot; cached results pass straight through.
        for await _ in classifyLibrary.execute(screenshots) {
            try Task.checkCancellation()
        }

        let classifications = await store.allClassifications()
        let verdicts = decisions.allDecisions()
        return screenshots.compactMap { shot in
            switch verdicts[shot.id] {
            case .keep:
                return nil
            case .markForDeletion:
                let category = classifications[shot.id]?.category ?? .other
                return ReviewItem(id: shot.id, category: category, byteSize: shot.byteSize)
            case nil:
                guard let classification = classifications[shot.id],
                      classification.disposition == .safeToDelete else { return nil }
                return ReviewItem(id: shot.id, category: classification.category, byteSize: shot.byteSize)
            }
        }
    }
}
