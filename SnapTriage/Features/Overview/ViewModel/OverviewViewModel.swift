//
//  OverviewViewModel.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class OverviewViewModel {

    enum Phase: Equatable {
        case idle
        /// Explaining why the app needs the library, *before* the system dialog.
        /// The permission sheet is the highest-stakes moment in the app and it
        /// used to fire over a blank screen.
        case primingAccess
        case loading
        case loaded
        case failed
    }

    /// Screen state that changes on user-visible events only. The running totals
    /// live in ``Progress`` instead: `@Observable` tracks stored properties, not
    /// struct fields, so keeping a figure that moves several times a second here
    /// would rebuild everything that reads `state` — the toolbar included.
    struct State: Equatable {
        var phase: Phase = .idle
        var errorMessage: String?
        var authorization: PhotoLibraryAuthorization = .notDetermined
        var features: [FeatureHighlight] = FeatureHighlight.defaults

        /// The user granted access to a hand-picked subset, so every figure on
        /// this screen describes that subset and nothing else.
        var isLimitedAccess: Bool { authorization == .limited }
    }

    /// Everything a running classification pass moves.
    struct Progress: Equatable {
        var summary: OverviewSummary = .empty
        var classifiedCount = 0
        /// When the current classification run started, and how much of the
        /// library it had already covered. Together these give an observed
        /// throughput to project the remainder against.
        var startedAt: Date?
        var startedFrom = 0

        var isComplete: Bool { classifiedCount >= summary.totalCount }

        /// Seconds left in the current pass, or `nil` until enough screenshots
        /// have completed to project honestly. A wrong ETA is worse than none,
        /// so the first few results only build the sample.
        var estimatedSecondsRemaining: Int? {
            guard let start = startedAt else { return nil }
            let completed = classifiedCount - startedFrom
            guard completed >= Self.minimumEtaSample else { return nil }
            let elapsed = Date.now.timeIntervalSince(start)
            guard elapsed > 0 else { return nil }
            let remaining = Double(summary.totalCount - classifiedCount)
            let seconds = remaining * elapsed / Double(completed)
            guard seconds.isFinite, seconds >= 1 else { return nil }
            return Int(seconds.rounded())
        }

        private static let minimumEtaSample = 8
    }

    enum Input {
        case onAppear
        case grantAccess
        case retry
        case openSystemSettings
        case addMorePhotos
    }

    private(set) var state = State()

    private(set) var progress = Progress()

    /// A pass is under way: the library is loaded, non-empty, and not yet fully
    /// classified. Spans both properties, so it lives on the view model.
    var isClassifying: Bool {
        state.phase == .loaded && progress.summary.totalCount > 0 && !progress.isComplete
    }

    var estimatedSecondsRemaining: Int? {
        isClassifying ? progress.estimatedSecondsRemaining : nil
    }

    private let requestAccess: RequestPhotoAccessUseCase
    private let loadScreenshots: LoadScreenshotsUseCase
    private let classifyLibrary: ClassifyLibraryUseCase
    private let observeLibrary: ObservePhotoLibraryUseCase
    private let router: OverviewRouter

    private enum TaskKind { case load, classify, observe }
    @ObservationIgnored private var tasks: [TaskKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var sizes: [Screenshot.ID: Int] = [:]

    init(
        requestAccess: RequestPhotoAccessUseCase,
        loadScreenshots: LoadScreenshotsUseCase,
        classifyLibrary: ClassifyLibraryUseCase,
        observeLibrary: ObservePhotoLibraryUseCase,
        router: OverviewRouter
    ) {
        self.requestAccess = requestAccess
        self.loadScreenshots = loadScreenshots
        self.classifyLibrary = classifyLibrary
        self.observeLibrary = observeLibrary
        self.router = router
    }

    func send(_ input: Input) {
        switch input {
        case .onAppear:
            guard state.phase == .idle else { return }
            // Asking for the library before the user has seen a single screen
            // spends the one permission prompt the app gets on a stranger. Show
            // what the app does first; prompt when they say yes.
            if requestAccess.current() == .notDetermined {
                state.phase = .primingAccess
            } else {
                loadFlow()
            }
        case .grantAccess:
            guard state.phase == .primingAccess else { return }
            loadFlow()
        case .retry:
            loadFlow()
        case .openSystemSettings:
            router.openSystemSettings()
        case .addMorePhotos:
            router.presentLimitedLibraryPicker()
        }
    }

    private func loadFlow() {
        run(.load) { [weak self] in
            guard let self else { return }
            self.tasks[.classify]?.cancel()
            self.state.phase = .loading
            self.state.errorMessage = nil
            self.progress = Progress()

            let authorization = await self.requestAccess.execute()
            if Task.isCancelled { return }
            self.state.authorization = authorization

            guard authorization.canAccessLibrary else {
                self.state.errorMessage = self.presentAuth(authorization)
                self.state.phase = .failed
                return
            }

            // Subscribe only now, with access in hand: this registers a
            // PhotoKit change observer, which has nothing to observe (and no
            // business reaching into the library) before the user has agreed.
            self.observeChanges()

            do {
                let screenshots = try await self.loadScreenshots.execute()
                try Task.checkCancellation()
                await self.applySnapshot(screenshots)
                self.state.phase = .loaded
            } catch is CancellationError {
                // superseded by a newer load
            } catch {
                self.state.errorMessage = self.present(error)
                self.state.phase = .failed
            }
        }
    }

    // Rebuilds the summary from a fresh library snapshot; shared by the initial
    // load and library-change refreshes. Persisted categories fold in one shot
    // so a warm pass renders fully formed — streaming them through classifyFlow
    // would spin the hero metric up from zero — and only genuinely
    // unclassified screenshots go to the pipeline.
    private func applySnapshot(_ screenshots: [Screenshot]) async {
        sizes = Dictionary(
            screenshots.map { ($0.id, $0.byteSize) },
            uniquingKeysWith: { first, _ in first }
        )

        let cached = await classifyLibrary.cachedClassifications()
        if Task.isCancelled { return }
        var summary = OverviewSummary()
        summary.totalCount = screenshots.count
        var pending: [Screenshot] = []
        for screenshot in screenshots {
            if let classification = cached[screenshot.id] {
                summary.add(bytes: screenshot.byteSize, disposition: classification.disposition)
            } else {
                pending.append(screenshot)
            }
        }
        progress.summary = summary
        progress.classifiedCount = screenshots.count - pending.count
        classifyFlow(pending, startingFrom: progress.classifiedCount)
    }

    // Silent re-sync after the library changed underneath us — a screenshot
    // taken while backgrounded, or assets deleted in Photos. No phase churn,
    // so the summary never flashes a loading state.
    private func refreshFlow() {
        guard state.phase == .loaded else { return }
        run(.load) { [weak self] in
            guard let self else { return }
            guard let screenshots = try? await self.loadScreenshots.execute(),
                  !Task.isCancelled
            else { return }
            await self.applySnapshot(screenshots)
        }
    }

    private func observeChanges() {
        guard tasks[.observe] == nil else { return }
        tasks[.observe] = Task { [weak self] in
            guard let stream = self?.observeLibrary.execute() else { return }
            for await _ in stream {
                guard let self, !Task.isCancelled else { return }
                self.refreshFlow()
            }
        }
    }

    // `base` is how many screenshots the cache already covered; the stream's
    // progress counts are relative to the pending slice handed to it.
    private func classifyFlow(_ screenshots: [Screenshot], startingFrom base: Int) {
        guard !screenshots.isEmpty else {
            progress.startedAt = nil
            return
        }
        progress.startedAt = .now
        progress.startedFrom = base
        run(.classify) { [weak self] in
            guard let self else { return }
            for await progress in self.classifyLibrary.execute(screenshots) {
                if Task.isCancelled { break }
                self.progress.classifiedCount = base + progress.completed
                guard let id = progress.id else { continue }
                if let classification = progress.classification {
                    self.progress.summary.add(
                        bytes: self.sizes[id] ?? 0,
                        disposition: classification.disposition
                    )
                } else {
                    self.progress.summary.unknownCount += 1
                }
            }
            self.progress.startedAt = nil
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
    func seedForPreview(_ summary: OverviewSummary) {
        state.phase = .loaded
        progress.summary = summary
        progress.classifiedCount = summary.totalCount
    }
    #endif
}
