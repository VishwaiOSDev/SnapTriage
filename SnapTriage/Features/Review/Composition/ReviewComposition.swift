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
        ocrStore: OCRStore,
        categoryStore: CategoryStore,
        decisionStore: TriageDecisionStore,
        router: ReviewRouter
    ) -> ReviewViewModel {
        let recognizer = VisionTextRecognitionService()

        let recognizeText = RecognizeScreenshotTextUseCase(
            imageLoader: service,
            recognizer: recognizer,
            store: ocrStore
        )
        let categorize = CategorizeScreenshotUseCase(
            categorizer: FallbackScreenshotCategorizer(),
            imageClassifier: VisionImageContentClassifier(),
            imageLoader: service
        )

        return ReviewViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadItems: LoadReviewItemsUseCase(
                loadScreenshots: LoadScreenshotsUseCase(service: service),
                classifyLibrary: ClassifyLibraryUseCase(
                    recognizeText: recognizeText,
                    categorize: categorize,
                    store: categoryStore
                ),
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
