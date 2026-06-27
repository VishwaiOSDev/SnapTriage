//
//  TriageComposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

enum TriageComposition {
    @MainActor
    static func make(
        service: PhotoLibraryService,
        ocrStore: OCRStore,
        router: TriageRouter
    ) -> TriageViewModel {
        let recognizer = VisionTextRecognitionService()
        return TriageViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            recognizeText: RecognizeScreenshotTextUseCase(imageLoader: service, recognizer: recognizer, store: ocrStore),
            categorize: CategorizeScreenshotUseCase(
                textCategorizer: FallbackScreenshotCategorizer(),
                imageClassifier: VisionImageContentClassifier(),
                imageLoader: service
            ),
            imageLoader: service,
            router: router
        )
    }
}
