//
//  CategorizeScreenshotUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation

struct CategorizeScreenshotUseCase {

    let textCategorizer: ScreenshotCategorizer

    /// Warms the text model while OCR is still running, hiding model load behind it.
    func prewarm() {
        textCategorizer.prewarm()
    }

    func execute(_ result: OCRResult) async -> ScreenshotCategory {
        await textCategorizer.category(for: result)
    }
}
