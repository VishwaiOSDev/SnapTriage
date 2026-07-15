//
//  TriageViewModel.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class TriageViewModel {

    enum Phase: Equatable { case idle, loading, loaded, failed }

    struct DecisionRecord: Equatable {
        let screenshotID: Screenshot.ID
        let decision: TriageDecision
    }

    struct State: Equatable {
        var authorization: PhotoLibraryAuthorization = .notDetermined
        var screenshots: [Screenshot] = []
        var classifications: [Screenshot.ID: ScreenshotClassification] = [:]
        var phase: Phase = .idle
        var errorMessage: String?
        var currentIndex = 0
        var keptCount = 0
        var markedCount = 0
        /// Deck entries that already have a verdict. The deck sorts newest
        /// first, so a screenshot taken mid-pass surfaces above already-swiped
        /// cards — advancing must skip decided cards, not step by one.
        var decidedIDs: Set<Screenshot.ID> = []
        /// Ordered session-only history. Persisted verdicts intentionally do
        /// not become undoable after relaunch because the store has no reliable
        /// action order; every swipe made in this session can be stepped back.
        var decisionHistory: [DecisionRecord] = []

        var current: Screenshot? {
            screenshots.indices.contains(currentIndex) ? screenshots[currentIndex] : nil
        }

        var upNext: Screenshot? {
            guard screenshots.indices.contains(currentIndex) else { return nil }
            return screenshots[(currentIndex + 1)...].first { !decidedIDs.contains($0.id) }
        }

        var isFinished: Bool {
            phase == .loaded && !screenshots.isEmpty && current == nil
        }

        /// Any stored or session verdict means restarting would discard work.
        var hasProgress: Bool { !decidedIDs.isEmpty }

        var canUndo: Bool { !decisionHistory.isEmpty }

        var lastDecision: TriageDecision? { decisionHistory.last?.decision }

        /// Moves to the next card without a verdict; lands on `count` (finished)
        /// when none remain.
        mutating func advance() {
            var next = currentIndex + 1
            while next < screenshots.count, decidedIDs.contains(screenshots[next].id) {
                next += 1
            }
            currentIndex = next
        }

        /// The verdict for a card, or `nil` while classification is still pending.
        /// A pending card must show a neutral "Analyzing…" state, never `.other`
        /// / safe-to-delete, so the view distinguishes "unknown yet" from "done".
        func classification(for screenshot: Screenshot) -> ScreenshotClassification? {
            classifications[screenshot.id]
        }
    }

    enum Input {
        case onAppear
        case retry
        case decide(TriageDecision)
        case undo
        case startOver
        case openSettings
        case clearError
        #if DEBUG
        case recategorizeAll
        #endif
    }

    private(set) var state = State()

    private let requestAccess: RequestPhotoAccessUseCase
    private let loadScreenshots: LoadScreenshotsUseCase
    private let classifyLibrary: ClassifyLibraryUseCase
    private let recordDecision: RecordTriageDecisionUseCase
    private let undoDecision: UndoTriageDecisionUseCase
    private let clearDecisions: ClearTriageDecisionsUseCase
    private let loadProgress: LoadTriageProgressUseCase
    private let observeLibrary: ObservePhotoLibraryUseCase
    private let imageLoader: PhotoLibraryService
    private let router: TriageRouter

    /// How many upcoming cards get classified ahead of the swipe position.
    private let classifyLookahead = 5

    private enum TaskKind { case load, classify, observe }
    @ObservationIgnored private var tasks: [TaskKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var isClassifying = false

    init(
        requestAccess: RequestPhotoAccessUseCase,
        loadScreenshots: LoadScreenshotsUseCase,
        classifyLibrary: ClassifyLibraryUseCase,
        recordDecision: RecordTriageDecisionUseCase,
        undoDecision: UndoTriageDecisionUseCase,
        clearDecisions: ClearTriageDecisionsUseCase,
        loadProgress: LoadTriageProgressUseCase,
        observeLibrary: ObservePhotoLibraryUseCase,
        imageLoader: PhotoLibraryService,
        router: TriageRouter
    ) {
        self.requestAccess = requestAccess
        self.loadScreenshots = loadScreenshots
        self.classifyLibrary = classifyLibrary
        self.recordDecision = recordDecision
        self.undoDecision = undoDecision
        self.clearDecisions = clearDecisions
        self.loadProgress = loadProgress
        self.observeLibrary = observeLibrary
        self.imageLoader = imageLoader
        self.router = router
    }

    func send(_ input: Input) {
        switch input {
        case .onAppear:
            if state.phase == .idle {
                loadFlow()
                observeChanges()
            }
        case .retry:
            loadFlow()
        case .decide(let decision):
            decide(decision)
        case .undo:
            undo()
        case .startOver:
            startOver()
        case .openSettings:
            router.openSettings()
        case .clearError:
            state.errorMessage = nil
        #if DEBUG
        case .recategorizeAll:
            recategorizeAll()
        #endif
        }
    }

    #if DEBUG
    // Debug-only: wipe every cached verdict and re-classify the whole library.
    // If the app backgrounds during this pass, the app-level coordinator joins
    // the same single-flight operations and owns durable completion/notification.
    private func recategorizeAll() {
        tasks[.classify]?.cancel()
        isClassifying = true

        tasks[.classify] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isClassifying = false
            }
            await self.classifyLibrary.clearCache()
            if Task.isCancelled { return }
            self.state.classifications = [:]

            for await progress in self.classifyLibrary.execute(self.state.screenshots) {
                if Task.isCancelled { return }
                if let id = progress.id, let classification = progress.classification {
                    self.state.classifications[id] = classification
                }
            }
            await self.classifyLibrary.flush()
        }
    }
    #endif

    // Transient read for the card image, not domain state, so bypasses send.
    func thumbnail(for id: Screenshot.ID, targetSize: CGSize) async -> UIImage? {
        // Triage switches presentation modes at runtime, so PhotoKit must return
        // the complete asset; a pre-cropped thumbnail cannot later be fitted.
        await imageLoader.thumbnail(for: id, targetSize: targetSize, mode: .fit)
    }

    private func loadFlow() {
        // Kick off the classifier's model load now, off the main actor, so it
        // overlaps the library fetch instead of stalling the first classify burst.
        let classifyLibrary = classifyLibrary
        Task.detached(priority: .utility) { classifyLibrary.prewarm() }

        run(.load) { [weak self] in
            guard let self else { return }
            self.state.phase = .loading
            self.state.errorMessage = nil

            let authorization = await self.requestAccess.execute()
            self.state.authorization = authorization

            guard authorization.canAccessLibrary else {
                self.state.errorMessage = self.presentAuth(authorization)
                self.state.phase = .failed
                return
            }

            do {
                let screenshots = try await self.loadScreenshots.execute()
                // Resume a pass in flight: persisted verdicts position the deck
                // at the first undecided card. A fresh pass (or Start Over,
                // which just cleared the store) lands at index 0 with zeroes.
                self.apply(screenshots)
                self.state.phase = .loaded
                self.classifyWindow()
            } catch is CancellationError {
                // superseded by newer load
            } catch {
                self.state.errorMessage = self.present(error)
                self.state.phase = .failed
            }
        }
    }

    // Positions deck state from a fresh library snapshot; shared by the initial
    // load and library-change refreshes.
    private func apply(_ screenshots: [Screenshot]) {
        let progress = loadProgress.execute(for: screenshots)
        state.screenshots = screenshots
        state.decidedIDs = progress.decidedIDs
        state.currentIndex = progress.firstUndecidedIndex
        state.keptCount = progress.keptCount
        state.markedCount = progress.markedCount
        // Loading or externally reordering the library establishes a new deck
        // baseline. Stored verdicts remain intact, but their interaction order
        // can no longer be reconstructed safely for undo.
        state.decisionHistory.removeAll()
    }

    // Silent re-sync after the library changed underneath us — a screenshot
    // taken while backgrounded, or assets deleted in Photos. No phase churn,
    // so the deck never flashes a loading state mid-session.
    private func refreshFlow() {
        guard state.phase == .loaded else { return }
        run(.load) { [weak self] in
            guard let self else { return }
            guard let screenshots = try? await self.loadScreenshots.execute(),
                  !Task.isCancelled,
                  screenshots.map(\.id) != self.state.screenshots.map(\.id)
            else { return }
            self.apply(screenshots)
            self.classifyWindow()
        }
    }

    private func observeChanges() {
        tasks[.observe] = Task { [weak self] in
            guard let stream = self?.observeLibrary.execute() else { return }
            for await _ in stream {
                guard let self, !Task.isCancelled else { return }
                self.refreshFlow()
            }
        }
    }

    private func decide(_ decision: TriageDecision) {
        guard let screenshot = state.current else { return }

        // Recorded synchronously so the verdict is in the store before the deck
        // advances: a Review load triggered afterwards can never miss this swipe.
        recordDecision.execute(decision, for: screenshot.id)

        switch decision {
        case .keep:            state.keptCount += 1
        case .markForDeletion: state.markedCount += 1
        }
        state.decidedIDs.insert(screenshot.id)
        state.decisionHistory.append(DecisionRecord(
            screenshotID: screenshot.id,
            decision: decision
        ))
        state.advance()
        classifyWindow()
    }

    private func undo() {
        while let record = state.decisionHistory.popLast() {
            guard let index = state.screenshots.firstIndex(where: { $0.id == record.screenshotID }),
                  let removedDecision = undoDecision.execute(for: record.screenshotID)
            else { continue }

            switch removedDecision {
            case .keep:            state.keptCount = max(0, state.keptCount - 1)
            case .markForDeletion: state.markedCount = max(0, state.markedCount - 1)
            }
            state.decidedIDs.remove(record.screenshotID)
            state.currentIndex = index
            classifyWindow()
            return
        }
    }

    /// Resets the pass without refetching PhotoKit or flashing a loading state.
    /// The loaded deck and its classifications remain valid presentation data.
    private func startOver() {
        guard state.hasProgress else { return }
        clearDecisions.execute()
        state.currentIndex = 0
        state.keptCount = 0
        state.markedCount = 0
        state.decidedIDs.removeAll()
        state.decisionHistory.removeAll()
        classifyWindow()
    }

    // Classifies the visible card plus a small lookahead so the category pill
    // is ready by the time a card surfaces. One task follows the swipe position,
    // re-deriving its window after each batch; restarting per swipe would cancel
    // in-flight OCR and pile a second burst on top of the first.
    private func classifyWindow() {
        guard !isClassifying else { return }
        isClassifying = true

        tasks[.classify] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isClassifying = false
            }

            // Failed classifications stay uncached; skipping already-attempted ids
            // bounds this run. The next swipe starts a fresh task that retries them.
            var attempted: Set<Screenshot.ID> = []
            while !Task.isCancelled {
                let window = self.state.screenshots
                    .dropFirst(self.state.currentIndex)
                    .prefix(self.classifyLookahead)
                    .filter { self.state.classifications[$0.id] == nil && !attempted.contains($0.id) }
                guard !window.isEmpty else { return }
                attempted.formUnion(window.map(\.id))

                for await progress in self.classifyLibrary.execute(Array(window)) {
                    if Task.isCancelled { return }
                    if let id = progress.id, let classification = progress.classification {
                        self.state.classifications[id] = classification
                    }
                }
            }
        }
    }

    // Replaces any in-flight task of the same kind: cancel stale, no reentrancy race.
    private func run(_ kind: TaskKind, _ operation: @escaping () async -> Void) {
        tasks[kind]?.cancel()
        tasks[kind] = Task { await operation() }
    }

    private func present(_ error: Error) -> String {
        switch error {
        case TriageError.photoAccessDenied:     return Strings.Error.accessDenied
        case TriageError.photoAccessRestricted: return Strings.Error.accessRestricted
        default:                                return Strings.Error.generic
        }
    }

    private func presentAuth(_ authorization: PhotoLibraryAuthorization) -> String {
        switch authorization {
        case .denied:     return Strings.Error.accessDenied
        case .restricted: return Strings.Error.accessRestricted
        default:          return Strings.Error.generic
        }
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }

    #if DEBUG
    func seedForPreview(_ screenshots: [Screenshot], categories: [Screenshot.ID: ScreenshotCategory]) {
        state.phase = .loaded
        state.authorization = .authorized
        state.screenshots = screenshots
        state.classifications = categories.mapValues {
            ScreenshotClassification(category: $0, confidence: .high, source: .heuristic)
        }
    }
    #endif
}
