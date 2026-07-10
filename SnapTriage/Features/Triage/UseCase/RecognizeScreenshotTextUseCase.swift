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

        let ordered = readingOrder(
            recognized.filter { $0.confidence >= minimumConfidence }
        )

        let result = OCRResult(screenshotID: screenshotID, lines: ordered)
        await store.save(result)
        return result
    }

    /// Vision coordinates start at the lower-left. Group adjacent observations into visual rows
    /// before sorting left-to-right, so card labels and their values stay together in the prompt.
    private func readingOrder(_ lines: [OCRLine]) -> [OCRLine] {
        let vertical = lines.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows: [[OCRLine]] = []

        for line in vertical {
            guard var row = rows.popLast() else {
                rows.append([line])
                continue
            }

            let rowMidY = row.map { $0.boundingBox.midY }.reduce(0, +) / CGFloat(row.count)
            let rowHeight = row.map { $0.boundingBox.height }.max() ?? 0
            let tolerance = max(rowHeight, line.boundingBox.height) * 0.75

            if abs(line.boundingBox.midY - rowMidY) <= tolerance {
                row.append(line)
                rows.append(row)
            } else {
                rows.append(row)
                rows.append([line])
            }
        }

        return rows.flatMap { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        }
    }
}
