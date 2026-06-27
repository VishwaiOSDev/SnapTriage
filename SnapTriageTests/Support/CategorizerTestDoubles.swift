//
//  CategorizerTestDoubles.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 20/06/26.
//

import CoreGraphics
import UIKit
@testable import SnapTriage

// MARK: - Test doubles

/// Returns a fixed category and records whether the system under test reached it.
final class StubScreenshotCategorizer: ScreenshotCategorizer, @unchecked Sendable {
    let result: ScreenshotCategory
    private(set) var categorizeCount = 0
    private(set) var prewarmCount = 0

    init(_ result: ScreenshotCategory) { self.result = result }

    func category(for result: OCRResult) async -> ScreenshotCategory {
        categorizeCount += 1
        return self.result
    }

    func prewarm() { prewarmCount += 1 }
}

/// Returns a configurable image verdict (or `nil` for "inconclusive").
struct StubImageContentClassifier: ImageContentClassifier {
    let result: ScreenshotCategory?
    func category(for image: CGImage) async -> ScreenshotCategory? { result }
}

/// Serves a preset `CGImage` and records whether the image path actually asked for it.
final class StubPhotoLibraryService: PhotoLibraryService, @unchecked Sendable {
    let image: CGImage?
    private(set) var cgImageRequested = false

    init(image: CGImage?) { self.image = image }

    func currentAuthorization() -> PhotoLibraryAuthorization { .authorized }
    func requestAuthorization() async -> PhotoLibraryAuthorization { .authorized }
    func fetchScreenshots() async -> [Screenshot] { [] }
    func thumbnail(for id: Screenshot.ID, targetSize: CGSize) async -> UIImage? { nil }
    func cgImage(for id: Screenshot.ID, longEdge: CGFloat) async -> CGImage? {
        cgImageRequested = true
        return image
    }
    func deleteScreenshots(_ ids: [Screenshot.ID]) async throws {}
}

// MARK: - Fixtures

enum Fixture {
    /// Builds an `OCRResult` whose transcript is the given text, one `OCRLine` per line.
    static func ocrResult(id: Screenshot.ID = "test", transcript: String) -> OCRResult {
        let lines = transcript
            .split(whereSeparator: \.isNewline)
            .map { OCRLine(text: String($0), confidence: 1, boundingBox: .zero) }
        return OCRResult(screenshotID: id, lines: lines)
    }

    /// A throwaway 1×1 bitmap — enough to satisfy the image path; pixels are never asserted.
    static func image() -> CGImage {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
