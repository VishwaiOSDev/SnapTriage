//
//  LoadReviewItemsUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation

/// Produces the deletion set for the Review screen. It drives the (cache-first)
/// classification pipeline to completion so every screenshot has a category in
/// the shared store, then folds in the user's triage swipes: a swipe always
/// overrides the classifier, and screenshots without a verdict fall back to the
/// classifier's safe-to-delete judgement. When Overview has already classified,
/// this is effectively free — every screenshot is a cache hit.
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

        let categories = await store.allCategories()
        let verdicts = decisions.allDecisions()
        return screenshots.compactMap { shot in
            switch verdicts[shot.id] {
            case .keep:
                return nil
            case .markForDeletion:
                return ReviewItem(id: shot.id, category: categories[shot.id] ?? .other, byteSize: shot.byteSize)
            case nil:
                guard let category = categories[shot.id],
                      category.disposition == .safeToDelete else { return nil }
                return ReviewItem(id: shot.id, category: category, byteSize: shot.byteSize)
            }
        }
    }
}
