//
//  ReviewViewModelTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 27/06/26.
//

import Testing
@testable import SnapTriage

@MainActor
@Suite("Review view model", .tags(.review))
struct ReviewViewModelTests {

    // Three safe-to-delete screenshots plus one useful, so the loaded set is "1","2","3".
    private func makeSUT(
        deleteError: Error? = nil,
        authorization: PhotoLibraryAuthorization = .authorized
    ) -> (ReviewViewModel, FakePhotoLibraryService) {
        let shots = [
            Fixture.screenshot(id: "1", byteSize: 100),
            Fixture.screenshot(id: "2", byteSize: 200),
            Fixture.screenshot(id: "3", byteSize: 300),
            Fixture.screenshot(id: "4", byteSize: 400)
        ]
        let service = FakePhotoLibraryService(
            authorization: authorization,
            screenshots: shots,
            deleteError: deleteError
        )
        let store = SeededCategoryStore([
            "1": .social,
            "2": .article,
            "3": .conversation,
            "4": .receipt
        ])
        let vm = ReviewViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadItems: Fixture.loadReviewItems(service: service, store: store),
            deleteScreenshots: DeleteScreenshotsUseCase(service: service),
            imageLoader: service,
            router: StubReviewRouter()
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

    @Test("Load surfaces only safe-to-delete items, all pre-selected")
    func loadPreSelectsAll() async {
        let (vm, _) = makeSUT()

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        #expect(vm.state.items.map(\.id) == ["1", "2", "3"])
        #expect(vm.state.selectedIDs == ["1", "2", "3"])
        #expect(vm.state.selectedCount == 3)
        #expect(vm.state.reclaimableBytes == 600)
    }

    @Test("Toggling deselects and updates reclaimable bytes")
    func toggleUpdatesSelection() async {
        let (vm, _) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.toggle("2"))

        #expect(vm.state.selectedIDs == ["1", "3"])
        #expect(vm.state.reclaimableBytes == 400)
        #expect(vm.state.hasSelection)

        vm.send(.toggle("2"))   // re-select
        #expect(vm.state.selectedIDs == ["1", "2", "3"])
    }

    @Test("Delete removes the selected items and forwards them to the library")
    func deleteRemovesSelected() async {
        let (vm, service) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.toggle("2"))   // keep "2", delete "1" and "3"
        vm.send(.deleteSelected)
        await waitUntil { vm.state.items.count == 1 }

        #expect(Set(service.deletedIDs) == ["1", "3"])
        #expect(vm.state.items.map(\.id) == ["2"])
        #expect(vm.state.errorMessage == nil)
        #expect(vm.state.isDeleting == false)
    }

    @Test("Cancelling the system sheet leaves the list untouched")
    func cancellationIsNoOp() async {
        let (vm, service) = makeSUT(deleteError: TriageError.deletionCancelled)
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.deleteSelected)
        await waitUntil { vm.state.isDeleting == false && service.deleteCallCount == 1 }

        #expect(vm.state.items.count == 3)
        #expect(vm.state.selectedIDs == ["1", "2", "3"])
        #expect(vm.state.errorMessage == nil)
    }

    @Test("A delete failure surfaces an error and keeps the items")
    func deleteFailureShowsError() async {
        let (vm, _) = makeSUT(deleteError: TriageError.deletionFailed)
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.deleteSelected)
        await waitUntil { vm.state.errorMessage != nil }

        #expect(vm.state.items.count == 3)
        #expect(vm.state.errorMessage == Strings.Review.deletionFailed)
    }

    @Test("Denied access fails with a presentable message")
    func deniedAccessFails() async {
        let (vm, _) = makeSUT(authorization: .denied)

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .failed }

        #expect(vm.state.items.isEmpty)
        #expect(vm.state.errorMessage == Strings.Error.accessDenied)
    }
}
