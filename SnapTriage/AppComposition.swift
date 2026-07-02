//
//  AppComposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation

/// App-level composition root. Builds the expensive, stateful dependencies once
/// — a single `PhotoKitLibraryService` (one `PHCachingImageManager`) and the
/// in-memory OCR/category/decision caches — and threads them into every feature.
///
/// Sharing the caches is what lets Review reuse Overview's classification work:
/// the classify pipeline is cache-first, so once Overview has run, opening Review
/// is near-instant. Features still never import one another; the app wires them.
@MainActor
final class AppComposition {

    private let service = PhotoKitLibraryService()
    private let ocrStore = InMemoryOCRStore()
    private let categoryStore = InMemoryCategoryStore()
    private let decisionStore = InMemoryTriageDecisionStore()

    func makeOverview(router: (any OverviewRouter)? = nil) -> OverviewViewModel {
        OverviewComposition.make(
            service: service,
            ocrStore: ocrStore,
            categoryStore: categoryStore,
            router: router ?? SystemOverviewRouter()
        )
    }

    func makeTriage(router: (any TriageRouter)? = nil) -> TriageViewModel {
        TriageComposition.make(
            service: service,
            ocrStore: ocrStore,
            categoryStore: categoryStore,
            decisionStore: decisionStore,
            router: router ?? SystemTriageRouter()
        )
    }

    func makeReview(router: (any ReviewRouter)? = nil) -> ReviewViewModel {
        ReviewComposition.make(
            service: service,
            ocrStore: ocrStore,
            categoryStore: categoryStore,
            decisionStore: decisionStore,
            router: router ?? SystemReviewRouter()
        )
    }
}
