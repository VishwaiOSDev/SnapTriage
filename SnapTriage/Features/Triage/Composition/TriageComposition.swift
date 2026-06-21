//
//  TriageComposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

enum TriageComposition {
    @MainActor
    static func make(router: TriageRouter) -> TriageViewModel {
        let service = PhotoKitLibraryService()
        let recognizer = VisionTextRecognitionService()
        let ocrStore = InMemoryOCRStore()
        return TriageViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            recognizeText: RecognizeScreenshotTextUseCase(imageLoader: service, recognizer: recognizer, store: ocrStore),
            categorize: CategorizeScreenshotUseCase(textCategorizer: FallbackScreenshotCategorizer()),
            imageLoader: service,
            router: router
        )
    }
}
