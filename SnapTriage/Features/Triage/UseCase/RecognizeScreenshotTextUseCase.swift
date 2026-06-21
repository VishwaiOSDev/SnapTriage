//
//  RecognizeScreenshotTextUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 10/06/26.
//

import CoreGraphics

struct RecognizeScreenshotTextUseCase {
    
    let imageLoader: PhotoLibraryService
    let recognizer: TextRecognitionService
    let store: OCRStore

    private let longEdge: CGFloat = 1600
    private let minimumConfidence: Float = 0.3

    func execute(screenshotID: Screenshot.ID) async throws -> OCRResult {
        if let cached = await store.result(for: screenshotID) {
            return cached
        }

        guard let image = await imageLoader.cgImage(for: screenshotID, longEdge: longEdge) else {
            throw TriageError.ocrFailed
        }

        let recognized = try await recognizer.recognize(image)

        let ordered = recognized
            .filter { $0.confidence >= minimumConfidence }
            .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }

        let result = OCRResult(screenshotID: screenshotID, lines: ordered)
        await store.save(result)
        return result
    }
}
