//
//  ReviewComposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation

enum ReviewComposition {
    @MainActor
    static func make(
        scope: ReviewScope = .triage,
        service: PhotoLibraryService,
        classifyLibrary: ClassifyLibraryUseCase,
        categoryStore: CategoryStore,
        ocrStore: OCRStore,
        decisionStore: TriageDecisionStore,
        router: ReviewRouter
    ) -> ReviewViewModel {
        return ReviewViewModel(
            scope: scope,
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadItems: LoadReviewItemsUseCase(
                loadScreenshots: LoadScreenshotsUseCase(service: service),
                classifyLibrary: classifyLibrary,
                store: categoryStore,
                decisions: decisionStore
            ),
            deleteScreenshots: DeleteScreenshotsUseCase(service: service),
            pruneRecords: PruneScreenshotRecordsUseCase(
                decisions: decisionStore,
                categories: categoryStore,
                ocr: ocrStore
            ),
            applyBulk: ApplyBulkTriageUseCase(store: decisionStore),
            revertBulk: RevertBulkTriageUseCase(store: decisionStore),
            imageLoader: service,
            router: router
        )
    }
}
