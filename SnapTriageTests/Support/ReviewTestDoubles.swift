//
//  ReviewTestDoubles.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 27/06/26.
//

import CoreGraphics
import UIKit
@testable import SnapTriage

// MARK: - Photo library fake

/// Serves a fixed screenshot list, records deletions, and can be told to fail
/// (or report user-cancellation) on delete. Used to drive the Review pipeline
/// end to end without touching PhotoKit.
final class FakePhotoLibraryService: PhotoLibraryService, @unchecked Sendable {
    var authorization: PhotoLibraryAuthorization
    var screenshots: [Screenshot]
    var deleteError: Error?

    private(set) var deletedIDs: [Screenshot.ID] = []
    private(set) var deleteCallCount = 0

    init(
        authorization: PhotoLibraryAuthorization = .authorized,
        screenshots: [Screenshot] = [],
        deleteError: Error? = nil
    ) {
        self.authorization = authorization
        self.screenshots = screenshots
        self.deleteError = deleteError
    }

    func currentAuthorization() -> PhotoLibraryAuthorization { authorization }
    func requestAuthorization() async -> PhotoLibraryAuthorization { authorization }
    func fetchScreenshots() async -> [Screenshot] { screenshots }
    func thumbnail(for id: Screenshot.ID, targetSize: CGSize) async -> UIImage? { nil }
    func cgImage(for id: Screenshot.ID, longEdge: CGFloat) async -> CGImage? { nil }

    func deleteScreenshots(_ ids: [Screenshot.ID]) async throws {
        deleteCallCount += 1
        if let deleteError { throw deleteError }
        deletedIDs.append(contentsOf: ids)
        screenshots.removeAll { ids.contains($0.id) }
    }
}

// MARK: - Category store fake

/// A category store pre-seeded with a fixed map. `allCategories()` returns the
/// seed so Review's classification pass is entirely cache hits.
actor SeededCategoryStore: CategoryStore {
    private var cache: [Screenshot.ID: ScreenshotCategory]

    init(_ seed: [Screenshot.ID: ScreenshotCategory]) {
        self.cache = seed
    }

    func category(for id: Screenshot.ID) -> ScreenshotCategory? { cache[id] }
    func save(_ category: ScreenshotCategory, for id: Screenshot.ID) { cache[id] = category }
    func allCategories() -> [Screenshot.ID: ScreenshotCategory] { cache }
}

// MARK: - Decision store fake

/// A decision store pre-seeded with a fixed map of triage swipes.
final class SeededTriageDecisionStore: TriageDecisionStore, @unchecked Sendable {
    private var cache: [Screenshot.ID: TriageDecision]

    init(_ seed: [Screenshot.ID: TriageDecision] = [:]) {
        self.cache = seed
    }

    func decision(for id: Screenshot.ID) -> TriageDecision? { cache[id] }
    func save(_ decision: TriageDecision, for id: Screenshot.ID) { cache[id] = decision }
    func allDecisions() -> [Screenshot.ID: TriageDecision] { cache }
    func removeAll() { cache.removeAll() }
}

// MARK: - Router

@MainActor
final class StubReviewRouter: ReviewRouter {
    private(set) var openSettingsCount = 0
    func openSettings() { openSettingsCount += 1 }
}

// MARK: - Fixtures

extension Fixture {
    static func screenshot(id: Screenshot.ID, byteSize: Int = 1_000_000) -> Screenshot {
        Screenshot(id: id, pixelWidth: 100, pixelHeight: 200, creationDate: nil, byteSize: byteSize)
    }

    /// A `LoadReviewItemsUseCase` whose categories are all cache hits, so OCR /
    /// classification are never invoked (their dependencies are inert).
    static func loadReviewItems(
        service: FakePhotoLibraryService,
        store: CategoryStore,
        decisions: TriageDecisionStore = SeededTriageDecisionStore()
    ) -> LoadReviewItemsUseCase {
        let recognize = RecognizeScreenshotTextUseCase(
            imageLoader: service,
            recognizer: InertTextRecognitionService(),
            store: InMemoryOCRStore()
        )
        let categorize = CategorizeScreenshotUseCase(
            textCategorizer: StubScreenshotCategorizer(.other),
            imageClassifier: StubImageContentClassifier(result: nil),
            imageLoader: service
        )
        return LoadReviewItemsUseCase(
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            classifyLibrary: ClassifyLibraryUseCase(
                recognizeText: recognize,
                categorize: categorize,
                store: store
            ),
            store: store,
            decisions: decisions
        )
    }
}

/// Never asked when categories are cached; throws if it ever is, to catch a
/// regression where Review re-runs OCR despite a populated store.
struct InertTextRecognitionService: TextRecognitionService {
    func recognize(_ image: CGImage) async throws -> [OCRLine] {
        throw TriageError.ocrFailed
    }
}
