//
//  OverviewViewModelTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 02/07/26.
//

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
private final class StubOverviewRouter: OverviewRouter {
    func openSettings() {}
}
