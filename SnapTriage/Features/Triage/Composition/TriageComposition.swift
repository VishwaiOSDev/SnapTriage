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
        classifyLibrary: ClassifyLibraryUseCase,
        decisionStore: TriageDecisionStore,
        router: TriageRouter
    ) -> TriageViewModel {
        return TriageViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            classifyLibrary: classifyLibrary,
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
