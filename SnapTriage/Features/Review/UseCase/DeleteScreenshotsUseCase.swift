//
//  DeleteScreenshotsUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation

/// Deletes the confirmed screenshots from the photo library. The system shows
/// its own confirmation sheet; declining surfaces as `TriageError.deletionCancelled`.
struct DeleteScreenshotsUseCase {

    let service: PhotoLibraryService

    func execute(_ ids: [Screenshot.ID]) async throws {
        guard !ids.isEmpty else { return }
        try await service.deleteScreenshots(ids)
    }
}
