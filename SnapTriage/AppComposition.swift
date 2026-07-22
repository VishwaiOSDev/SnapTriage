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

    private let service: PhotoKitLibraryService
    private let ocrStore: FileBackedOCRStore
    private let categoryStore: FileBackedCategoryStore
    private let decisionStore: FileBackedTriageDecisionStore
    /// One metrics sink across features, so aggregate routing/timing counts (how
    /// much of the library needed the model) are cumulative rather than per-tab.
    private let metrics: OSLogClassificationMetrics
    /// One process-wide engine. All feature requests and background passes join
    /// the same per-screenshot work through this use case.
    private let classifyLibrary: ClassifyLibraryUseCase

    init() {
        let service = PhotoKitLibraryService()
        let ocrStore = FileBackedOCRStore(directory: URL.cachesDirectory)
        let categoryStore = FileBackedCategoryStore(directory: URL.cachesDirectory)
        let decisionStore = FileBackedTriageDecisionStore(directory: URL.applicationSupportDirectory)
        let metrics = OSLogClassificationMetrics()
        let recognizeText = RecognizeScreenshotTextUseCase(
            imageLoader: service,
            recognizer: VisionTextRecognitionService(),
            store: ocrStore
        )
        let categorize = CategorizeScreenshotUseCase(imageLoader: service, metrics: metrics)
        let engine = LibraryClassificationEngine(
            recognizeText: recognizeText,
            categorize: categorize,
            store: categoryStore
        )

        self.service = service
        self.ocrStore = ocrStore
        self.categoryStore = categoryStore
        self.decisionStore = decisionStore
        self.metrics = metrics
        self.classifyLibrary = ClassifyLibraryUseCase(engine: engine)
    }

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
            classifyLibrary: classifyLibrary,
            router: router ?? SystemOverviewRouter()
        )
    }

    func makeTriage(router: (any TriageRouter)? = nil) -> TriageViewModel {
        TriageComposition.make(
            service: service,
            classifyLibrary: classifyLibrary,
            decisionStore: decisionStore,
            router: router ?? SystemTriageRouter()
        )
    }

    func makeReview(router: (any ReviewRouter)? = nil) -> ReviewViewModel {
        ReviewComposition.make(
            service: service,
            classifyLibrary: classifyLibrary,
            categoryStore: categoryStore,
            ocrStore: ocrStore,
            decisionStore: decisionStore,
            router: router ?? SystemReviewRouter()
        )
    }

    /// Builds the suspended-library classifier from the same shared service and
    /// stores as the foreground features, so its background pass writes into the
    /// exact cache the deck and Overview read from.
    func makeBackgroundClassificationCoordinator(
        navigation: AppNavigation
    ) -> BackgroundClassificationCoordinator {
        return BackgroundClassificationCoordinator(
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            classifyLibrary: classifyLibrary,
            decisions: decisionStore,
            onOpenTriage: { navigation.presentTriage() }
        )
    }
}
