//
//  TriageViewModelTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 02/07/26.
//

import Testing
import CoreGraphics
@testable import SnapTriage

@MainActor
@Suite("Triage view model", .tags(.triage))
struct TriageViewModelTests {

    private func makeSUT(
        decisions: SeededTriageDecisionStore = SeededTriageDecisionStore()
    ) -> (TriageViewModel, SeededTriageDecisionStore, FakePhotoLibraryService) {
        let shots = [
            Fixture.screenshot(id: "1"),
            Fixture.screenshot(id: "2"),
            Fixture.screenshot(id: "3"),
            Fixture.screenshot(id: "4")
        ]
        let service = FakePhotoLibraryService(screenshots: shots)
        let store = SeededCategoryStore([
            "1": .social,
            "2": .article,
            "3": .conversation,
            "4": .receipt
        ])
        let vm = TriageViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            loadScreenshots: LoadScreenshotsUseCase(service: service),
            classifyLibrary: Fixture.classifyLibrary(service: service, store: store),
            recordDecision: RecordTriageDecisionUseCase(store: decisions),
            undoDecision: UndoTriageDecisionUseCase(store: decisions),
            clearDecisions: ClearTriageDecisionsUseCase(store: decisions),
            loadProgress: LoadTriageProgressUseCase(store: decisions),
            observeLibrary: ObservePhotoLibraryUseCase(service: service),
            imageLoader: service,
            router: StubTriageRouter()
        )
        return (vm, decisions, service)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, ticks: Int = 5000) async {
        var count = 0
        while !condition() && count < ticks {
            await Task.yield()
            count += 1
        }
    }

    @Test("A fresh pass starts at the first card with zeroed counters")
    func freshPassStartsAtZero() async {
        let (vm, _, _) = makeSUT()

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        #expect(vm.state.currentIndex == 0)
        #expect(vm.state.keptCount == 0)
        #expect(vm.state.markedCount == 0)
        #expect(!vm.state.hasProgress)
    }

    @Test("Stored verdicts resume the deck at the first undecided card")
    func resumesAtFirstUndecided() async {
        let decisions = SeededTriageDecisionStore(["1": .keep, "2": .markForDeletion])
        let (vm, _, _) = makeSUT(decisions: decisions)

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        #expect(vm.state.currentIndex == 2)
        #expect(vm.state.current?.id == "3")
        #expect(vm.state.keptCount == 1)
        #expect(vm.state.markedCount == 1)
        #expect(vm.state.hasProgress)
    }

    @Test("A fully decided deck resumes on the finished screen")
    func fullyDecidedDeckIsFinished() async {
        let decisions = SeededTriageDecisionStore([
            "1": .keep, "2": .keep, "3": .markForDeletion, "4": .keep
        ])
        let (vm, _, _) = makeSUT(decisions: decisions)

        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        #expect(vm.state.isFinished)
        #expect(vm.state.keptCount == 3)
        #expect(vm.state.markedCount == 1)
    }

    @Test("Start Over clears the stored verdicts and rewinds the deck")
    func startOverRewinds() async {
        let decisions = SeededTriageDecisionStore(["1": .keep, "2": .keep])
        let (vm, _, service) = makeSUT(decisions: decisions)
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }
        let loadedScreenshots = vm.state.screenshots
        let fetchCount = service.fetchCallCount

        vm.send(.startOver)

        #expect(decisions.allDecisions().isEmpty)
        #expect(vm.state.phase == .loaded)
        #expect(vm.state.screenshots == loadedScreenshots)
        #expect(vm.state.currentIndex == 0)
        #expect(vm.state.keptCount == 0)
        #expect(vm.state.markedCount == 0)
        #expect(!vm.state.hasProgress)
        #expect(!vm.state.canUndo)

        // Restart is an in-memory operation: it must not flash loading or
        // issue another PhotoKit fetch on the next run-loop turn.
        await Task.yield()
        #expect(service.fetchCallCount == fetchCount)
    }

    @Test("A library change folds a new screenshot in without losing progress")
    func libraryChangeMergesNewScreenshot() async {
        let (vm, _, service) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.decide(.keep))              // "1"
        vm.send(.decide(.markForDeletion))   // "2"
        #expect(vm.state.current?.id == "3")

        // A screenshot taken mid-pass sorts newest-first, above swiped cards.
        service.screenshots.insert(Fixture.screenshot(id: "0"), at: 0)
        service.simulateLibraryChange()
        await waitUntil { vm.state.screenshots.count == 5 }

        // New card surfaces, counters survive, and advancing skips the
        // already-decided cards sitting behind it.
        #expect(vm.state.current?.id == "0")
        #expect(vm.state.keptCount == 1)
        #expect(vm.state.markedCount == 1)
        #expect(vm.state.upNext?.id == "3")

        vm.send(.decide(.keep))
        #expect(vm.state.current?.id == "3")
    }

    @Test("A swipe lands in the store before the deck advances")
    func swipeRecordsBeforeAdvancing() async {
        let (vm, decisions, _) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.decide(.markForDeletion))

        // Synchronous contract: no waiting between the swipe and the read.
        #expect(decisions.decision(for: "1") == .markForDeletion)
        #expect(vm.state.currentIndex == 1)
        #expect(vm.state.markedCount == 1)
    }

    @Test("Triage requests an uncropped thumbnail for Fit and Fill")
    func triageRequestsFittedThumbnail() async {
        let (vm, _, service) = makeSUT()

        _ = await vm.thumbnail(for: "1", targetSize: CGSize(width: 300, height: 500))

        #expect(service.requestedThumbnailMode == .fit)
    }

    @Test("Undo restores the latest card and removes its stored verdict")
    func undoRestoresLatestCard() async {
        let (vm, decisions, _) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.decide(.keep))
        vm.send(.decide(.markForDeletion))
        #expect(vm.state.current?.id == "3")

        vm.send(.undo)

        #expect(vm.state.current?.id == "2")
        #expect(decisions.decision(for: "2") == nil)
        #expect(decisions.decision(for: "1") == .keep)
        #expect(vm.state.keptCount == 1)
        #expect(vm.state.markedCount == 0)
        #expect(vm.state.canUndo)
    }

    @Test("Undo can step backward through every swipe from this session")
    func repeatedUndoIsLastInFirstOut() async {
        let (vm, decisions, _) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.decide(.keep))
        vm.send(.decide(.markForDeletion))
        vm.send(.undo)
        vm.send(.undo)

        #expect(vm.state.current?.id == "1")
        #expect(decisions.allDecisions().isEmpty)
        #expect(vm.state.keptCount == 0)
        #expect(vm.state.markedCount == 0)
        #expect(!vm.state.canUndo)
    }

    @Test("Undo reopens the last card from the finished screen")
    func undoReopensFinishedDeck() async {
        let (vm, decisions, _) = makeSUT()
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.decide(.keep))
        vm.send(.decide(.keep))
        vm.send(.decide(.markForDeletion))
        vm.send(.decide(.keep))
        #expect(vm.state.isFinished)

        vm.send(.undo)

        #expect(!vm.state.isFinished)
        #expect(vm.state.current?.id == "4")
        #expect(decisions.decision(for: "4") == nil)
        #expect(vm.state.keptCount == 2)
        #expect(vm.state.markedCount == 1)
    }

    @Test("Persisted verdicts are not treated as ordered undo history")
    func restoredProgressDoesNotInventUndoHistory() async {
        let decisions = SeededTriageDecisionStore(["1": .keep])
        let (vm, _, _) = makeSUT(decisions: decisions)
        vm.send(.onAppear)
        await waitUntil { vm.state.phase == .loaded }

        vm.send(.undo)

        #expect(vm.state.current?.id == "2")
        #expect(decisions.decision(for: "1") == .keep)
        #expect(!vm.state.canUndo)
    }
}

@MainActor
private final class StubTriageRouter: TriageRouter {
    func openSettings() {}
}
