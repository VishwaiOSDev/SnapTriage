//
//  CategorizeScreenshotUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import CoreGraphics

struct CategorizeScreenshotUseCase {

    let categorizer: ScreenshotCategorizer
    let imageClassifier: ImageContentClassifier
    let imageLoader: PhotoLibraryService

    /// Fewer recognized words than this means the screen is image-led (a photo, a
    /// signature, a scanned card) — the transcript can't be trusted, so ask the pixels.
    private let minimumWords = 4
    private let longEdge: CGFloat = 1024

    /// Warms the language model while OCR is still running, hiding model load behind it.
    func prewarm() {
        categorizer.prewarm()
    }

    func execute(_ result: OCRResult) async -> ScreenshotCategory {
        // iOS 27's Foundation Model can inspect the actual screenshot. Route every screen
        // through it: app and game interfaces are often text-rich, so word count is not a
        // reliable proxy for whether pixels matter.
        if #available(iOS 27.0, *) {
            let image = await classifierImage(for: result)
            let category = await categorizer.category(for: result, image: image)
            guard category == .other, let image else { return category }
            return await imageClassifier.category(for: image) ?? .other
        }

        // On iOS 26, the system model is text-only. Preserve the inexpensive Vision fallback
        // for image-led screenshots, then defer to OCR classification when it is inconclusive.
        if isTextSparse(result), let image = await classifierImage(for: result),
           let visual = await imageClassifier.category(for: image) {
            return visual
        }

        let category = await categorizer.category(for: result, image: nil)
        guard category == .other,
              let image = await classifierImage(for: result) else {
            return category
        }
        return await imageClassifier.category(for: image) ?? .other
    }

    private func classifierImage(for result: OCRResult) async -> CGImage? {
        await imageLoader.cgImage(for: result.screenshotID, longEdge: longEdge)
    }

    private func isTextSparse(_ result: OCRResult) -> Bool {
        let words = result.transcript.split { $0.isWhitespace || $0.isNewline }
        return words.count < minimumWords
    }
}
