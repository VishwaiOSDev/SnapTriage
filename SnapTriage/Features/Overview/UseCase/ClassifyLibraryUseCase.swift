//
//  ClassifyLibraryUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

struct ClassifyLibraryUseCase {
    let recognizeText: RecognizeScreenshotTextUseCase
    let categorize: CategorizeScreenshotUseCase
    let store: CategoryStore

    struct Progress: Sendable {
        let id: Screenshot.ID?
        let category: ScreenshotCategory?
        let completed: Int
        let total: Int
    }

    func execute(_ screenshots: [Screenshot]) -> AsyncStream<Progress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
