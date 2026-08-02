//
//  SettingsComposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import Foundation

enum SettingsComposition {
    @MainActor
    static func make(
        service: PhotoLibraryService,
        classifyLibrary: ClassifyLibraryUseCase,
        ocrStore: OCRStore,
        notifications: NotificationSettingsReading,
        router: SettingsRouter
    ) -> SettingsViewModel {
        SettingsViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            cache: ManageClassificationCacheUseCase(
                classifyLibrary: classifyLibrary,
                ocr: ocrStore
            ),
            notifications: notifications,
            router: router
        )
    }
}
