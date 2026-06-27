//
//  AppComposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation

/// App-level composition root. Builds the expensive, stateful dependencies once
/// — a single `PhotoKitLibraryService` (one `PHCachingImageManager`) and the
/// in-memory OCR/category caches — and threads them into every feature.
///
/// Sharing the caches is what lets Review reuse Overview's classification work:
/// the classify pipeline is cache-first, so once Overview has run, opening Review
/// is near-instant. Features still never import one another; the app wires them.
@MainActor
final class AppComposition {

    private let service = PhotoKitLibraryService()
    private let ocrStore = InMemoryOCRStore()
    private let categoryStore = InMemoryCategoryStore()

    func makeOverview(router: OverviewRouter = SystemOverviewRouter()) -> OverviewViewModel {
        OverviewComposition.make(
            service: service,
            ocrStore: ocrStore,
            categoryStore: categoryStore,
            router: router
        )
    }

    func makeTriage(router: TriageRouter = SystemTriageRouter()) -> TriageViewModel {
        TriageComposition.make(
            service: service,
            ocrStore: ocrStore,
            router: router
        )
    }

    func makeReview(router: ReviewRouter = SystemReviewRouter()) -> ReviewViewModel {
        ReviewComposition.make(
            service: service,
            ocrStore: ocrStore,
            categoryStore: categoryStore,
            router: router
        )
    }
}
