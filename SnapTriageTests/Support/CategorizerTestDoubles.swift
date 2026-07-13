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

/// A foundation-model stand-in that records how it was driven — call count, and
/// whether an image reached it — so tests can assert the cascade invoked the
/// model exactly as expected (zero calls for confident heuristics, one for
/// ambiguous screens) without touching Apple Intelligence.
final class RecordingModelClassifier: ScreenshotModelClassifier, @unchecked Sendable {
    let verdict: ModelVerdict?
    private(set) var callCount = 0
    private(set) var receivedImage = false
    private(set) var prewarmCount = 0

    /// `verdict == nil` models an unavailable / failed model.
    init(_ verdict: ModelVerdict?) { self.verdict = verdict }

    convenience init(category: ScreenshotCategory?, usedImage: Bool = false) {
        self.init(category.map { ModelVerdict(category: $0, usedImage: usedImage) })
    }

    func classify(ocr: OCRResult, image: CGImage?) async -> ModelVerdict? {
        callCount += 1
        receivedImage = image != nil
        return verdict
    }

    func prewarm() { prewarmCount += 1 }
}

/// Records routing/timing calls so tests can count heuristic / Vision / model
/// resolutions and needs-review outcomes.
final class RecordingClassificationMetrics: ClassificationMetrics, @unchecked Sendable {
    private(set) var engineCalls: [ClassificationEngine: Int] = [:]
    private(set) var resolutions: [ClassificationSource: Int] = [:]
    private(set) var imageEngineCalls = 0
    private(set) var needsReviewCount = 0
    private(set) var failureCount = 0

    func record(_ stage: ClassificationStage, _ duration: Duration) {}
    func recordEngine(_ engine: ClassificationEngine, usedImage: Bool) {
        engineCalls[engine, default: 0] += 1
        if usedImage { imageEngineCalls += 1 }
    }
    func recordResolution(_ source: ClassificationSource) { resolutions[source, default: 0] += 1 }
    func recordNeedsReview() { needsReviewCount += 1 }
    func recordFailure() { failureCount += 1 }

    var heuristicCalls: Int { engineCalls[.heuristic] ?? 0 }
    var visionCalls: Int { engineCalls[.vision] ?? 0 }
    var foundationModelCalls: Int { engineCalls[.foundationModel] ?? 0 }
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
    func thumbnail(
        for id: Screenshot.ID,
        targetSize: CGSize,
        mode: PhotoThumbnailMode
    ) async -> UIImage? { nil }
    func cgImage(for id: Screenshot.ID, longEdge: CGFloat) async -> CGImage? {
        cgImageRequested = true
        return image
    }
    func deleteScreenshots(_ ids: [Screenshot.ID]) async throws {}
    func libraryChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
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

    /// Builds the cheap-first orchestrator with the real heuristic and injectable
    /// Vision / model / image doubles, so tests exercise the actual cascade.
    static func categorize(
        vision: ImageContentClassifier = StubImageContentClassifier(result: nil),
        model: ScreenshotModelClassifier = RecordingModelClassifier(nil),
        loader: PhotoLibraryService,
        metrics: ClassificationMetrics = NoopClassificationMetrics()
    ) -> CategorizeScreenshotUseCase {
        CategorizeScreenshotUseCase(
            heuristic: HeuristicScreenshotCategorizer(),
            vision: vision,
            model: model,
            imageLoader: loader,
            metrics: metrics
        )
    }
}
