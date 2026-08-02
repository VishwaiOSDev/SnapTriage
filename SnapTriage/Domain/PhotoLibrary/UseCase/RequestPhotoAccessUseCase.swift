//
//  RequestPhotoAccessUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

struct RequestPhotoAccessUseCase {
    let service: PhotoLibraryService

    /// Reads the status without prompting, so a feature can decide whether it is
    /// about to show the user a system dialog.
    func current() -> PhotoLibraryAuthorization {
        service.currentAuthorization()
    }

    func execute() async -> PhotoLibraryAuthorization {
        let current = service.currentAuthorization()
        guard current == .notDetermined else { return current }
        return await service.requestAuthorization()
    }
}
