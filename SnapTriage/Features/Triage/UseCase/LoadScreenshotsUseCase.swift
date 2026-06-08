//
//  LoadScreenshotsUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

struct LoadScreenshotsUseCase {
    let service: PhotoLibraryService

    func execute() async throws -> [Screenshot] {
        switch service.currentAuthorization() {
        case .denied:     throw TriageError.photoAccessDenied
        case .restricted: throw TriageError.photoAccessRestricted
        case .authorized, .limited, .notDetermined: break
        }
        return await service.fetchScreenshots()
    }
}
