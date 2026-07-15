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
        classifyLibrary: ClassifyLibraryUseCase,
        router: OverviewRouter
    ) -> OverviewViewModel {
        return OverviewViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            classifyLibrary: classifyLibrary,
            observeLibrary: ObservePhotoLibraryUseCase(service: service),
            router: router
        )
    }
}
