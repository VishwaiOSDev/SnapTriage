//
//  OverviewComposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

enum OverviewComposition {
    @MainActor
    static func make(
        service: PhotoLibraryService,
        ocrStore: OCRStore,
        categoryStore: CategoryStore,
        metrics: ClassificationMetrics = OSLogClassificationMetrics(),
        router: OverviewRouter
    ) -> OverviewViewModel {
        let recognizer = VisionTextRecognitionService()

        let recognizeText = RecognizeScreenshotTextUseCase(
            imageLoader: service,
            recognizer: recognizer,
            store: ocrStore
        )
        let categorize = CategorizeScreenshotUseCase(imageLoader: service, metrics: metrics)

        return OverviewViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            classifyLibrary: ClassifyLibraryUseCase(
                recognizeText: recognizeText,
                categorize: categorize,
                store: categoryStore
            ),
            observeLibrary: ObservePhotoLibraryUseCase(service: service),
            router: router
        )
    }
}
