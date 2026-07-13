//
//  AppComposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation

/// App-level composition root. Builds the expensive, stateful dependencies once
/// — a single `PhotoKitLibraryService` (one `PHCachingImageManager`) and the
/// disk-backed OCR/category/decision stores — and threads them into every feature.
///
/// Sharing the stores is what lets Review reuse Overview's classification work:
/// the classify pipeline is cache-first, so once Overview has run, opening Review
/// is near-instant. Features still never import one another; the app wires them.
///
/// Store placement: decisions are user intent and live in Application Support;
/// OCR and categories are recomputable caches and live in Caches, where the
/// system may purge them.
@MainActor
final class AppComposition {

    private let service = PhotoKitLibraryService()
    private let ocrStore = FileBackedOCRStore(directory: URL.cachesDirectory)
    private let categoryStore = FileBackedCategoryStore(directory: URL.cachesDirectory)
    private let decisionStore = FileBackedTriageDecisionStore(directory: URL.applicationSupportDirectory)
    /// One metrics sink across features, so aggregate routing/timing counts (how
    /// much of the library needed the model) are cumulative rather than per-tab.
    private let metrics = OSLogClassificationMetrics()

    /// Forces pending store writes to disk; called when the scene backgrounds,
    /// after which the process may be killed without further notice.
    func flushStores() {
        decisionStore.flush()
        categoryStore.flush()
        ocrStore.flush()
    }

    func makeOverview(router: (any OverviewRouter)? = nil) -> OverviewViewModel {
        OverviewComposition.make(
            service: service,
            ocrStore: ocrStore,
            categoryStore: categoryStore,
            metrics: metrics,
            router: router ?? SystemOverviewRouter()
        )
    }

    func makeTriage(router: (any TriageRouter)? = nil) -> TriageViewModel {
        TriageComposition.make(
            service: service,
            ocrStore: ocrStore,
            categoryStore: categoryStore,
            decisionStore: decisionStore,
            metrics: metrics,
            router: router ?? SystemTriageRouter()
        )
    }

    func makeReview(router: (any ReviewRouter)? = nil) -> ReviewViewModel {
        ReviewComposition.make(
            service: service,
            ocrStore: ocrStore,
            categoryStore: categoryStore,
            decisionStore: decisionStore,
            metrics: metrics,
            router: router ?? SystemReviewRouter()
        )
    }
}
