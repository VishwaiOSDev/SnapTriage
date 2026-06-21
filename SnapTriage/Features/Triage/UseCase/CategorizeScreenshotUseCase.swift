//
//  CategorizeScreenshotUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import CoreGraphics

struct CategorizeScreenshotUseCase {

    let textCategorizer: ScreenshotCategorizer
    let imageClassifier: ImageContentClassifier
    let imageLoader: PhotoLibraryService

    /// Fewer recognized words than this means the screen is image-led (a photo, a
    /// signature, a scanned card) — the transcript can't be trusted, so ask the pixels.
    private let minimumWords = 4
    private let longEdge: CGFloat = 1024

    /// Warms the text model while OCR is still running, hiding model load behind it.
    func prewarm() {
        textCategorizer.prewarm()
    }

    func execute(_ result: OCRResult) async -> ScreenshotCategory {
        guard isTextSparse(result) else {
            return await textCategorizer.category(for: result)
        }
        if let image = await imageLoader.cgImage(for: result.screenshotID, longEdge: longEdge),
           let visual = await imageClassifier.category(for: image) {
            return visual
        }
        return await textCategorizer.category(for: result)
    }

    private func isTextSparse(_ result: OCRResult) -> Bool {
        let words = result.transcript.split { $0.isWhitespace || $0.isNewline }
        return words.count < minimumWords
    }
}
