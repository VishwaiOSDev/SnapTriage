//
//  OverviewViewModelTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 02/07/26.
//

import CoreGraphics
import Testing
@testable import SnapTriage

@MainActor
@Suite("Overview view model", .tags(.overview))
struct OverviewViewModelTests {

    private func makeSUT(
        cached: [Screenshot.ID: ScreenshotCategory]
    ) -> (OverviewViewModel, FakePhotoLibraryService) {
        let shots = [
            Fixture.screenshot(id: "1", byteSize: 100),
            Fixture.screenshot(id: "2", byteSize: 200),
            Fixture.screenshot(id: "3", byteSize: 300),
            Fixture.screenshot(id: "4", byteSize: 400)
        ]
        let service = FakePhotoLibraryService(screenshots: shots)
        let vm = OverviewViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            classifyLibrary: Fixture.classifyLibrary(service: service, store: SeededCategoryStore(cached)),
            observeLibrary: ObservePhotoLibraryUseCase(service: service),
            router: StubOverviewRouter()
        )
        return (vm, service)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, ticks: Int = 5000) async {
        var count = 0
        while !condition() && count < ticks {
            await Task.yield()
            count += 1
        }
    }

    @Test("A fully cached library renders the summary complete at first load")
    func warmCacheRendersSummaryFullyFormed() async {
        let (vm, _) = makeSUT(cached: [
            "1": .social,          // safe, 100
            "2": .article,         // safe, 200
            "3": .receipt,         // useful, 300
            "4": .conversation     // safe, 400
        ])

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        // The regression this guards: persisted categories used to stream
        // through classifyFlow, animating the hero metric up from zero.
        #expect(vm.state.summary.safeBytes == 700)
        #expect(vm.state.summary.usefulBytes == 300)
        #expect(vm.state.summary.totalCount == 4)
        #expect(vm.state.classifiedCount == 4)
        #expect(vm.state.isClassifying == false)
    }

    @Test("A partially cached library folds the hits and streams the rest")
    func partialCacheStreamsOnlyRemainder() async {
        let (vm, _) = makeSUT(cached: ["1": .social, "2": .receipt])

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        // Cached portion lands with the load itself.
        #expect(vm.state.summary.safeBytes == 100)
        #expect(vm.state.summary.usefulBytes == 200)
        #expect(vm.state.classifiedCount >= 2)

        // Uncached "3"/"4" run the inert pipeline and finish as unknown.
        await waitUntil { vm.state.classifiedCount == 4 }
        #expect(vm.state.summary.unknownCount == 2)
        #expect(vm.state.isClassifying == false)
    }

    @Test("A library change refreshes the summary without a loading flash")
    func libraryChangeRefreshesInPlace() async {
        let (vm, service) = makeSUT(cached: [
            "1": .social, "2": .article, "3": .conversation, "4": .receipt
        ])
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }
        #expect(vm.state.summary.totalCount == 4)

        // Screenshot taken while backgrounded; observer fires on return.
        service.screenshots.insert(Fixture.screenshot(id: "5", byteSize: 500), at: 0)
        service.simulateLibraryChange()
        await waitUntil { vm.state.summary.totalCount == 5 }

        #expect(vm.state.phase == .loaded)
        // Known categories folded straight back in; the new shot runs the
        // (inert) pipeline and lands as unknown.
        #expect(vm.state.summary.safeBytes == 600)
        #expect(vm.state.summary.usefulBytes == 400)
        await waitUntil { vm.state.classifiedCount == 5 }
        #expect(vm.state.summary.unknownCount == 1)
    }
}

@MainActor
@Suite("App navigation")
struct AppNavigationTests {

    @Test("A notification route waits until the scene is active")
    func notificationRouteWaitsForActiveScene() {
        let navigation = AppNavigation()

        navigation.requestSelection(.triage)
        #expect(navigation.selection == .overview)

        navigation.sceneDidBecomeActive()
        #expect(navigation.selection == .triage)
    }

    @Test("A notification route is queued again while backgrounded")
    func backgroundRouteIsQueued() {
        let navigation = AppNavigation()
        navigation.sceneDidBecomeActive()
        navigation.requestSelection(.triage)
        navigation.sceneDidLeaveActive()

        navigation.requestSelection(.review)
        #expect(navigation.selection == .triage)

        navigation.sceneDidBecomeActive()
        #expect(navigation.selection == .review)
    }
}

@Suite("Classification execution")
struct ClassificationExecutionTests {

    @Test("Overlapping consumers join one OCR and categorization operation")
    func overlappingConsumersAreSingleFlight() async {
        let screenshot = Fixture.screenshot(id: "single-flight")
        let service = StubPhotoLibraryService(image: Fixture.image())
        let recognizer = CountingTextRecognitionService()
        let classify = ClassifyLibraryUseCase(
            recognizeText: RecognizeScreenshotTextUseCase(
                imageLoader: service,
                recognizer: recognizer,
                store: InMemoryOCRStore()
            ),
            categorize: Fixture.categorize(loader: service),
            store: InMemoryCategoryStore()
        )

        async let first = collect(classify.execute([screenshot]))
        async let second = collect(classify.execute([screenshot]))
        let (firstResults, secondResults) = await (first, second)

        #expect(firstResults.count == 1)
        #expect(secondResults.count == 1)
        #expect(firstResults.first?.classification?.category == .receipt)
        #expect(secondResults.first?.classification?.category == .receipt)
        #expect(await recognizer.callCount == 1)
    }

    @MainActor
    @Test("A completion notification is sent only after OCR and categories are durable")
    func coordinatorFlushesBeforeNotifying() async {
        let screenshot = Fixture.screenshot(id: "durable")
        let service = StubPhotoLibraryService(
            image: Fixture.image(),
            screenshots: [screenshot]
        )
        let ocrStore = TrackingOCRStore()
        let categoryStore = TrackingCategoryStore()
        let notifier = FlushCheckingNotifier(ocrStore: ocrStore, categoryStore: categoryStore)
        let completionStore = InMemoryClassificationCompletionStore()
        let classify = ClassifyLibraryUseCase(
            recognizeText: RecognizeScreenshotTextUseCase(
                imageLoader: service,
                recognizer: CountingTextRecognitionService(),
                store: ocrStore
            ),
            categorize: Fixture.categorize(loader: service),
            store: categoryStore
        )
        let coordinator = BackgroundClassificationCoordinator(
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            classifyLibrary: classify,
            decisions: InMemoryTriageDecisionStore(),
            notifier: notifier,
            completionStore: completionStore
        )

        let result = await coordinator.runClassificationPass()

        #expect(result.outcome == .completed)
        #expect(result.newlyClassified == 1)
        #expect(result.remaining == 0)
        #expect(result.notificationPending == false)
        #expect(notifier.notifiedCounts == [1])
        #expect(notifier.observedDurableWrites)
        #expect(completionStore.pendingCount == nil)
    }

    private func collect(
        _ stream: AsyncStream<ClassifyLibraryUseCase.Progress>
    ) async -> [ClassifyLibraryUseCase.Progress] {
        var results: [ClassifyLibraryUseCase.Progress] = []
        for await result in stream { results.append(result) }
        return results
    }
}

private actor CountingTextRecognitionService: TextRecognitionService {
    private(set) var callCount = 0

    func recognize(_ image: CGImage) async throws -> [OCRLine] {
        callCount += 1
        try await Task.sleep(for: .milliseconds(30))
        return [
            OCRLine(text: "Subtotal $38.00", confidence: 1, boundingBox: .zero),
            OCRLine(text: "Tax $4.00", confidence: 1, boundingBox: .zero),
            OCRLine(text: "Total $42.00", confidence: 1, boundingBox: .zero),
            OCRLine(text: "Paid", confidence: 1, boundingBox: .zero)
        ]
    }
}

private actor TrackingOCRStore: OCRStore {
    private var results: [Screenshot.ID: OCRResult] = [:]
    private(set) var wasFlushed = false

    func result(for id: Screenshot.ID) -> OCRResult? { results[id] }
    func save(_ result: OCRResult) { results[result.screenshotID] = result }
    func remove(_ ids: [Screenshot.ID]) { ids.forEach { results[$0] = nil } }
    func flushPendingWrites() { wasFlushed = true }
}

private actor TrackingCategoryStore: CategoryStore {
    private var classifications: [Screenshot.ID: ScreenshotClassification] = [:]
    private(set) var wasFlushed = false

    func classification(for id: Screenshot.ID) -> ScreenshotClassification? { classifications[id] }
    func save(_ classification: ScreenshotClassification, for id: Screenshot.ID) {
        classifications[id] = classification
    }
    func allClassifications() -> [Screenshot.ID: ScreenshotClassification] { classifications }
    func remove(_ ids: [Screenshot.ID]) { ids.forEach { classifications[$0] = nil } }
    func flushPendingWrites() { wasFlushed = true }
    #if DEBUG
    func removeAll() { classifications.removeAll() }
    #endif
}

@MainActor
private final class FlushCheckingNotifier: ClassificationNotifying {
    let ocrStore: TrackingOCRStore
    let categoryStore: TrackingCategoryStore
    private(set) var notifiedCounts: [Int] = []
    private(set) var observedDurableWrites = false

    init(ocrStore: TrackingOCRStore, categoryStore: TrackingCategoryStore) {
        self.ocrStore = ocrStore
        self.categoryStore = categoryStore
    }

    func requestAuthorizationIfNeeded() async throws {}

    func notifyReady(count: Int) async throws -> ClassificationNotificationDelivery {
        notifiedCounts.append(count)
        let ocrWasFlushed = await ocrStore.wasFlushed
        let categoriesWereFlushed = await categoryStore.wasFlushed
        observedDurableWrites = ocrWasFlushed && categoriesWereFlushed
        return .delivered
    }
}

@MainActor
private final class InMemoryClassificationCompletionStore: ClassificationCompletionStoring {
    private(set) var pendingCount: Int?
    func savePendingCount(_ count: Int) { pendingCount = count }
    func clearPendingCount() { pendingCount = nil }
}

@MainActor
private final class StubOverviewRouter: OverviewRouter {
    func openSettings() {}
}
