//
//  LoadReviewItemsUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation

/// Produces the "safe to delete" set for the Review screen. It drives the
/// (cache-first) classification pipeline to completion so every screenshot has a
/// category in the shared store, then keeps only the safe-to-delete ones in
/// library order (newest first). When Overview has already classified, this is
/// effectively free — every screenshot is a cache hit.
struct LoadReviewItemsUseCase {

    let loadScreenshots: LoadScreenshotsUseCase
    let classifyLibrary: ClassifyLibraryUseCase
    let store: CategoryStore

    func execute() async throws -> [ReviewItem] {
        let screenshots = try await loadScreenshots.execute()
        guard !screenshots.isEmpty else { return [] }

        // Ensure a category exists for each screenshot; cached results pass straight through.
        for await _ in classifyLibrary.execute(screenshots) {
            try Task.checkCancellation()
        }

        let categories = await store.allCategories()
        return screenshots.compactMap { shot in
            guard let category = categories[shot.id],
                  category.disposition == .safeToDelete else { return nil }
            return ReviewItem(id: shot.id, category: category, byteSize: shot.byteSize)
        }
    }
}
