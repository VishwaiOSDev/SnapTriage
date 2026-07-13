//
//  LoadReviewItemsUseCaseTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 27/06/26.
//

import Testing
@testable import SnapTriage

@Suite("Load review items", .tags(.review))
struct LoadReviewItemsUseCaseTests {

    @Test("Keeps only safe-to-delete items, in library order", .tags(.fast))
    func keepsSafeToDeleteInOrder() async throws {
        let shots = [
            Fixture.screenshot(id: "1", byteSize: 100),   // social        -> safe
            Fixture.screenshot(id: "2", byteSize: 200),   // receipt       -> useful
            Fixture.screenshot(id: "3", byteSize: 300),   // conversation  -> safe
            Fixture.screenshot(id: "4", byteSize: 400)    // otp           -> useful
        ]
        let service = FakePhotoLibraryService(screenshots: shots)
        let store = SeededCategoryStore([
            "1": .social,
            "2": .receipt,
            "3": .conversation,
            "4": .otp
        ])
        let sut = Fixture.loadReviewItems(service: service, store: store)

        let items = try await sut.execute()

        #expect(items.map(\.id) == ["1", "3"])
        #expect(items.map(\.category) == [.social, .conversation])
        #expect(items.map(\.byteSize) == [100, 300])
    }

    @Test("Empty library yields no items", .tags(.fast))
    func emptyLibrary() async throws {
        let service = FakePhotoLibraryService(screenshots: [])
        let sut = Fixture.loadReviewItems(service: service, store: SeededCategoryStore([:]))

        let items = try await sut.execute()

        #expect(items.isEmpty)
    }

    @Test("All-useful library yields no items", .tags(.fast))
    func allUseful() async throws {
        let shots = [Fixture.screenshot(id: "1"), Fixture.screenshot(id: "2")]
        let service = FakePhotoLibraryService(screenshots: shots)
        let store = SeededCategoryStore(["1": .receipt, "2": .identity])
        let sut = Fixture.loadReviewItems(service: service, store: store)

        let items = try await sut.execute()

        #expect(items.isEmpty)
    }

    @Test("Triage swipes override the classifier's judgement", .tags(.fast))
    func swipesOverrideClassifier() async throws {
        let shots = [
            Fixture.screenshot(id: "1", byteSize: 100),   // social  -> safe, but user kept it
            Fixture.screenshot(id: "2", byteSize: 200),   // receipt -> useful, but user marked it
            Fixture.screenshot(id: "3", byteSize: 300)    // social  -> safe, no verdict
        ]
        let service = FakePhotoLibraryService(screenshots: shots)
        let store = SeededCategoryStore([
            "1": .social,
            "2": .receipt,
            "3": .social
        ])
        let decisions = SeededTriageDecisionStore([
            "1": .keep,
            "2": .markForDeletion
        ])
        let sut = Fixture.loadReviewItems(service: service, store: store, decisions: decisions)

        let items = try await sut.execute()

        #expect(items.map(\.id) == ["2", "3"])
        #expect(items.map(\.category) == [.receipt, .social])
    }

    @Test("A marked screenshot without a cached category still surfaces", .tags(.fast))
    func markedWithoutCategorySurfaces() async throws {
        let shots = [Fixture.screenshot(id: "1", byteSize: 100)]
        let service = FakePhotoLibraryService(screenshots: shots)
        let store = SeededCategoryStore(["1": .other])   // classifier gave up -> .other, still safe
        let decisions = SeededTriageDecisionStore(["1": .markForDeletion])
        let sut = Fixture.loadReviewItems(service: service, store: store, decisions: decisions)

        let items = try await sut.execute()

        #expect(items.map(\.id) == ["1"])
    }

    @Test("Needs-review classifications are never pre-selected for deletion", .tags(.fast))
    func needsReviewNotPreselected() async throws {
        let shots = [
            Fixture.screenshot(id: "1", byteSize: 100),   // shopping    -> needsReview
            Fixture.screenshot(id: "2", byteSize: 200),   // other/low   -> needsReview
            Fixture.screenshot(id: "3", byteSize: 300)    // social/low  -> needsReview
        ]
        let service = FakePhotoLibraryService(screenshots: shots)
        let store = SeededCategoryStore(classifications: [
            "1": ScreenshotClassification(category: .shopping, confidence: .high, source: .heuristic),
            "2": ScreenshotClassification(category: .other, confidence: .low, source: .fallback),
            "3": ScreenshotClassification(category: .social, confidence: .low, source: .foundationModelText)
        ])
        let sut = Fixture.loadReviewItems(service: service, store: store)

        let items = try await sut.execute()

        #expect(items.isEmpty)
    }

    @Test("A cache hit builds items without re-running OCR", .tags(.fast))
    func cacheHitSkipsOCR() async throws {
        // The inert recognizer throws if OCR runs; a fully cached store must
        // never reach it, so the safe-to-delete item still surfaces.
        let shots = [Fixture.screenshot(id: "1", byteSize: 100)]
        let service = FakePhotoLibraryService(screenshots: shots)
        let sut = Fixture.loadReviewItems(service: service, store: SeededCategoryStore(["1": .social]))

        let items = try await sut.execute()

        #expect(items.map(\.id) == ["1"])
    }

    @Test("Denied access throws before classifying", .tags(.fast))
    func deniedThrows() async {
        let service = FakePhotoLibraryService(authorization: .denied)
        let sut = Fixture.loadReviewItems(service: service, store: SeededCategoryStore([:]))

        await #expect(throws: TriageError.photoAccessDenied) {
            _ = try await sut.execute()
        }
    }
}
