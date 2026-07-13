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
        categoryStore: CategoryStore,
        decisionStore: TriageDecisionStore,
        metrics: ClassificationMetrics = OSLogClassificationMetrics(),
        router: TriageRouter
    ) -> TriageViewModel {
        let recognizer = VisionTextRecognitionService()

        let recognizeText = RecognizeScreenshotTextUseCase(
            imageLoader: service,
            recognizer: recognizer,
            store: ocrStore
        )
        let categorize = CategorizeScreenshotUseCase(imageLoader: service, metrics: metrics)

        return TriageViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            classifyLibrary: ClassifyLibraryUseCase(
                recognizeText: recognizeText,
                categorize: categorize,
                store: categoryStore
            ),
            recordDecision: RecordTriageDecisionUseCase(store: decisionStore),
            undoDecision: UndoTriageDecisionUseCase(store: decisionStore),
            clearDecisions: ClearTriageDecisionsUseCase(store: decisionStore),
            loadProgress: LoadTriageProgressUseCase(store: decisionStore),
            observeLibrary: ObservePhotoLibraryUseCase(service: service),
            imageLoader: service,
            router: router
        )
    }
}
