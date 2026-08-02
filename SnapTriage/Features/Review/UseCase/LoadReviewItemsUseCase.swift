//
//  LoadReviewItemsUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation

/// Produces the candidate set for the Review screen. It drives the (cache-first)
/// classification pipeline to completion so every screenshot has a classification
/// in the shared store, then folds in the user's triage swipes: a swipe always
/// overrides the classifier, and screenshots without a verdict are included only
/// when the classifier's retention judgement is `safeToDelete`. Needs-review and
/// useful screenshots never surface at all.
///
/// Each item carries how it got here. A classifier verdict the user has never
/// seen is a *suggestion*, not a decision, so it is tagged `.suggested` and the
/// Review screen keeps it out of the default deletion selection. Only swipes the
/// user actually made come back as `.userMarked`.
///
/// When Overview has already classified, this is effectively free — every
/// screenshot is a cache hit.
struct LoadReviewItemsUseCase {

    let loadScreenshots: LoadScreenshotsUseCase
    let classifyLibrary: ClassifyLibraryUseCase
    let store: CategoryStore
    let decisions: TriageDecisionStore

    func execute(scope: ReviewScope = .triage) async throws -> [ReviewItem] {
        let screenshots = try await loadScreenshots.execute()
        guard !screenshots.isEmpty else { return [] }

        return switch scope {
        case .triage:
            try await triageItems(screenshots)
        case .category(let category):
            await categoryItems(screenshots, in: category)
        }
    }

    private func triageItems(_ screenshots: [Screenshot]) async throws -> [ReviewItem] {
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
                return item(shot, classifications[shot.id]?.category ?? .other, .userMarked)
            case nil:
                guard let classification = classifications[shot.id],
                      classification.disposition == .safeToDelete else { return nil }
                return item(shot, classification.category, .suggested)
            }
        }
    }

    private func categoryItems(
        _ screenshots: [Screenshot],
        in category: ScreenshotCategory
    ) async -> [ReviewItem] {
        let classifications = await classifyLibrary.cachedClassifications()
        let verdicts = decisions.allDecisions()
        return screenshots.compactMap { shot in
            switch verdicts[shot.id] {
            case .keep:
                return nil
            case .markForDeletion:
                // Screenshots already marked belong with their bucket rather than
                // hidden from it: deleting half a category and leaving the rest
                // invisible is how a user loses track of what they decided.
                guard (classifications[shot.id]?.category ?? .other) == category else { return nil }
                return item(shot, category, .userMarked)
            case nil:
                guard classifications[shot.id]?.category == category else { return nil }
                return item(shot, category, .suggested)
            }
        }
    }

    private func item(
        _ shot: Screenshot,
        _ category: ScreenshotCategory,
        _ source: ReviewItem.Source
    ) -> ReviewItem {
        ReviewItem(
            id: shot.id,
            category: category,
            byteSize: shot.byteSize,
            source: source,
            creationDate: shot.creationDate
        )
    }
}
