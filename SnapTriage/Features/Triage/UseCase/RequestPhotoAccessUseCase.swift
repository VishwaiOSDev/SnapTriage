//
//  RequestPhotoAccessUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

struct RequestPhotoAccessUseCase {
    let service: PhotoLibraryService

    func execute() async -> PhotoLibraryAuthorization {
        let current = service.currentAuthorization()
        guard current == .notDetermined else { return current }
        return await service.requestAuthorization()
    }
}
