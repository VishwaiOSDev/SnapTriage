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
        scope: ReviewScope = .triage,
        deleteError: Error? = nil,
        authorization: PhotoLibraryAuthorization = .authorized,
        decisions: SeededTriageDecisionStore = SeededTriageDecisionStore()
    ) -> (ReviewViewModel, FakePhotoLibraryService, SeededCategoryStore) {
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
        let vm = Fixture.reviewViewModel(
            scope: scope,
            service: service,
            store: store,
            decisions: decisions
        )
        return (vm, service, store)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, ticks: Int = 5000) async {
        var count = 0
        while !condition() && count < ticks {
            await Task.yield()
            count += 1
        }
    }

    @Test("A classifier suggestion the user has never seen is never pre-selected")
    func suggestionsAreNotPreSelected() async {
        let (vm, _, _) = makeSUT()

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        // This is the safety property: with no swipes recorded, everything on
        // screen is a guess, so tapping delete straight away deletes nothing.
        #expect(vm.state.items.map(\.id) == ["1", "2", "3"])
        #expect(vm.state.suggestedItems.map(\.id) == ["1", "2", "3"])
        #expect(vm.state.selectedIDs.isEmpty)
        #expect(!vm.state.hasSelection)
        #expect(vm.state.reclaimableBytes == 0)
    }

    @Test("Only the user's own swipes arrive pre-selected")
    func userMarkedItemsArePreSelected() async {
        let decisions = SeededTriageDecisionStore(["4": .markForDeletion])
        let (vm, _, _) = makeSUT(decisions: decisions)

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        // "4" is a receipt the classifier calls useful; the swipe outranks it.
        #expect(vm.state.markedItems.map(\.id) == ["4"])
        #expect(vm.state.suggestedItems.map(\.id) == ["1", "2", "3"])
        #expect(vm.state.selectedIDs == ["4"])
        #expect(vm.state.reclaimableBytes == 400)
    }

    @Test("Select-all arms every suggestion, and toggles back off")
    func selectAllSuggestions() async {
        let (vm, _, _) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.toggleAllSuggestions)

        #expect(vm.state.selectedIDs == ["1", "2", "3"])
        #expect(vm.state.areAllSuggestionsSelected)
        #expect(vm.state.reclaimableBytes == 600)

        vm.send(.toggleAllSuggestions)
        #expect(vm.state.selectedIDs.isEmpty)
    }

    @Test("Toggling deselects and updates reclaimable bytes")
    func toggleUpdatesSelection() async {
        let (vm, _, _) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }
        vm.send(.toggleAllSuggestions)

        vm.send(.toggle("2"))

        #expect(vm.state.selectedIDs == ["1", "3"])
        #expect(vm.state.reclaimableBytes == 400)
        #expect(vm.state.hasSelection)
        #expect(!vm.state.areAllSuggestionsSelected)

        vm.send(.toggle("2"))   // re-select
        #expect(vm.state.selectedIDs == ["1", "2", "3"])
    }

    @Test("A manual deselection survives a reload instead of being re-armed")
    func deselectionSurvivesReload() async {
        let decisions = SeededTriageDecisionStore(["4": .markForDeletion])
        let (vm, _, _) = makeSUT(decisions: decisions)
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }
        #expect(vm.state.selectedIDs == ["4"])

        vm.send(.toggle("4"))
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        #expect(vm.state.selectedIDs.isEmpty)
    }

    @Test("Select-all arms the whole screen, and toggles back off")
    func selectAllEverything() async {
        let decisions = SeededTriageDecisionStore(["4": .markForDeletion])
        let (vm, _, _) = makeSUT(decisions: decisions)
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }
        #expect(!vm.state.areAllSelected)

        vm.send(.toggleSelectAll)

        #expect(vm.state.selectedIDs == ["1", "2", "3", "4"])
        #expect(vm.state.areAllSelected)

        vm.send(.toggleSelectAll)
        #expect(vm.state.selectedIDs.isEmpty)
        #expect(!vm.state.areAllSelected)
    }

    @Test("A reload over existing items refreshes in place instead of blanking the grid")
    func reloadKeepsContentOnScreen() async {
        let (vm, _, _) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.onAppear)

        // The grid stays mounted for the whole reload: phase never drops back
        // to .loading once there is something to show.
        var sawRefreshing = false
        var ticks = 0
        while ticks < 5000 {
            #expect(vm.state.phase == .loaded)
            if vm.state.isRefreshing { sawRefreshing = true }
            if sawRefreshing && !vm.state.isRefreshing { break }
            await Task.yield()
            ticks += 1
        }

        #expect(sawRefreshing)
        #expect(vm.state.items.count == 3)
    }

    @Test("An empty selection reads as a real zero, not \"Zero KB\"")
    func emptySelectionFormatsAsZero() async {
        let (vm, _, _) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        #expect(MetricFormatter.size(vm.state.reclaimableBytes) == "0 bytes")
    }

    @Test("Delete removes the selected items and forwards them to the library")
    func deleteRemovesSelected() async {
        let (vm, service, _) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }
        vm.send(.toggleAllSuggestions)

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
        let (vm, service, _) = makeSUT(deleteError: TriageError.deletionCancelled)
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }
        vm.send(.toggleAllSuggestions)

        vm.send(.deleteSelected)
        await waitUntil { vm.state.isDeleting == false && service.deleteCallCount == 1 }

        #expect(vm.state.items.count == 3)
        #expect(vm.state.selectedIDs == ["1", "2", "3"])
        #expect(vm.state.errorMessage == nil)
    }

    @Test("A delete failure surfaces an error and keeps the items")
    func deleteFailureShowsError() async {
        let (vm, _, _) = makeSUT(deleteError: TriageError.deletionFailed)
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }
        vm.send(.toggleAllSuggestions)

        vm.send(.deleteSelected)
        await waitUntil { vm.state.errorMessage != nil }

        #expect(vm.state.items.count == 3)
        #expect(vm.state.errorMessage == Strings.Review.deletionFailed)
    }

    @Test("Successful delete prunes the stored records for the deleted ids")
    func deletePrunesStores() async {
        let decisions = SeededTriageDecisionStore(["1": .markForDeletion, "2": .keep])
        let (vm, _, categories) = makeSUT(decisions: decisions)
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        // "2" was swiped keep, so the loaded set is "1" and "3"; delete both.
        vm.send(.toggleAllSuggestions)
        vm.send(.deleteSelected)
        await waitUntil { vm.state.items.isEmpty }

        #expect(decisions.decision(for: "1") == nil)
        #expect(decisions.decision(for: "2") == .keep)
        #expect(await categories.classification(for: "1") == nil)
        #expect(await categories.classification(for: "3") == nil)
        #expect(await categories.classification(for: "2")?.category == .article)
    }

    @Test("Cancelling the system sheet prunes nothing")
    func cancellationPrunesNothing() async {
        let decisions = SeededTriageDecisionStore(["1": .markForDeletion])
        let (vm, service, categories) = makeSUT(
            deleteError: TriageError.deletionCancelled,
            decisions: decisions
        )
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.deleteSelected)
        await waitUntil { vm.state.isDeleting == false && service.deleteCallCount == 1 }

        #expect(decisions.decision(for: "1") == .markForDeletion)
        #expect(await categories.classification(for: "1")?.category == .social)
    }

    // MARK: - Category scope

    @Test("A category scope shows the whole bucket, including what triage hides")
    func categoryScopeShowsUsefulBucket() async {
        // "4" is a receipt: `useful`, so the triage inbox never offers it. The
        // user asked for the bucket, so the bucket is what they get.
        let (vm, _, _) = makeSUT(scope: .category(.receipt))

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        #expect(vm.state.items.map(\.id) == ["4"])
        #expect(vm.state.suggestedItems.map(\.id) == ["4"])
    }

    @Test("Opening a category selects nothing, so no one can delete a bucket blind")
    func categoryScopeSelectsNothing() async {
        let (vm, _, _) = makeSUT(scope: .category(.social))

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        #expect(vm.state.items.map(\.id) == ["1"])
        #expect(vm.state.selectedIDs.isEmpty)
        #expect(!vm.state.hasSelection)
    }

    @Test("A category scope still arrives armed for the user's own swipes")
    func categoryScopeKeepsUserMarks() async {
        let decisions = SeededTriageDecisionStore(["4": .markForDeletion])
        let (vm, _, _) = makeSUT(scope: .category(.receipt), decisions: decisions)

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        #expect(vm.state.markedItems.map(\.id) == ["4"])
        #expect(vm.state.selectedIDs == ["4"])
    }

    @Test("Keep-all retires the category without deleting anything, and undoes cleanly")
    func keepAllIsReversible() async {
        let decisions = SeededTriageDecisionStore()
        let (vm, service, _) = makeSUT(scope: .category(.social), decisions: decisions)
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }
        #expect(vm.state.items.map(\.id) == ["1"])

        vm.send(.keepAll)
        await waitUntil { vm.state.items.isEmpty }

        #expect(decisions.decision(for: "1") == .keep)
        #expect(service.deleteCallCount == 0)
        #expect(vm.state.lastReceipt?.count == 1)

        vm.send(.undoBulk)
        await waitUntil { !vm.state.items.isEmpty }

        #expect(decisions.decision(for: "1") == nil)
        #expect(vm.state.lastReceipt == nil)
    }

    @Test("Keep-all is refused in the triage inbox, which has no category to retire")
    func keepAllIsCategoryOnly() async {
        let decisions = SeededTriageDecisionStore()
        let (vm, _, _) = makeSUT(decisions: decisions)
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.keepAll)

        #expect(vm.state.lastReceipt == nil)
        #expect(decisions.allDecisions().isEmpty)
    }

    @Test("Denied access fails with a presentable message")
    func deniedAccessFails() async {
        let (vm, _, _) = makeSUT(authorization: .denied)

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .failed }

        #expect(vm.state.items.isEmpty)
        #expect(vm.state.errorMessage == Strings.Error.accessDenied)
    }
}
