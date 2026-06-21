//
//  CategorizeScreenshotUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation

struct CategorizeScreenshotUseCase {

    let categorizer: ScreenshotCategorizer

    func execute(_ result: OCRResult) -> ScreenshotCategory {
        categorizer.category(for: result)
    }
}
