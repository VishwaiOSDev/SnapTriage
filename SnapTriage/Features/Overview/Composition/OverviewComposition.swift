//
//  OverviewComposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

enum OverviewComposition {
    @MainActor
    static func make(router: OverviewRouter) -> OverviewViewModel {
        let service = PhotoKitLibraryService()
        let recognizer = VisionTextRecognitionService()
        let ocrStore = InMemoryOCRStore()
        let categoryStore = InMemoryCategoryStore()

        let recognizeText = RecognizeScreenshotTextUseCase(
            imageLoader: service,
            recognizer: recognizer,
            store: ocrStore
        )
        let categorize = CategorizeScreenshotUseCase(
            textCategorizer: FallbackScreenshotCategorizer(),
            imageClassifier: VisionImageContentClassifier(),
            imageLoader: service
        )

        return OverviewViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            classifyLibrary: ClassifyLibraryUseCase(
                recognizeText: recognizeText,
                categorize: categorize,
                store: categoryStore
            ),
            router: router
        )
    }
}
