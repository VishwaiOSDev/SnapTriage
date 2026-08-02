//
//  ObservePhotoLibraryUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 02/07/26.
//

import Foundation

/// Surfaces photo library change events so features can refresh their data
/// when the library moves underneath them — a screenshot taken while the app
/// was backgrounded, or assets deleted in the Photos app.
struct ObservePhotoLibraryUseCase {

    let service: PhotoLibraryService

    func execute() -> AsyncStream<Void> {
        service.libraryChanges()
    }
}
