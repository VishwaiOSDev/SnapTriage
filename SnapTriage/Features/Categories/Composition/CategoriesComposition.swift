//
//  CategoriesComposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import Foundation

enum CategoriesComposition {
    @MainActor
    static func make(
        service: PhotoLibraryService,
        classifyLibrary: ClassifyLibraryUseCase,
        decisionStore: TriageDecisionStore
    ) -> CategoriesViewModel {
        CategoriesViewModel(
            loadBreakdown: LoadCategoryBreakdownUseCase(
                loadScreenshots: LoadScreenshotsUseCase(service: service),
                classifyLibrary: classifyLibrary,
                decisions: decisionStore
            )
        )
    }
}
