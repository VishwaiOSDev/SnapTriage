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
        service: PhotoLibraryService,
        classifyLibrary: ClassifyLibraryUseCase,
        categoryStore: CategoryStore,
        ocrStore: OCRStore,
        decisionStore: TriageDecisionStore,
        router: ReviewRouter
    ) -> ReviewViewModel {
        return ReviewViewModel(
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
            imageLoader: service,
            router: router
        )
    }
}
