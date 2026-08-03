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
        enum AnalysisPhase: Equatable {
            case idle
            case running
            case complete
            case incomplete
        }

        var summary: OverviewSummary = .empty
        /// Verdicts that exist in the shared category store. An attempted but
        /// failed screenshot is deliberately not included: relaunch restoration
        /// uses the same persisted truth, so both paths now agree on completion.
        var classifiedCount = 0
        var failedCount = 0
        var analysisPhase: AnalysisPhase = .idle
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
        case sceneBecameActive
        case grantAccess
        case retry
        case retryAnalysis
        case openSystemSettings
        case addMorePhotos
    }

    private(set) var state = State()

    private(set) var progress = Progress()

    /// A pass is under way: the library is loaded, non-empty, and not yet fully
    /// classified. Spans both properties, so it lives on the view model.
    var isClassifying: Bool {
        state.phase == .loaded && progress.analysisPhase == .running
    }

    var hasIncompleteAnalysis: Bool {
        state.phase == .loaded && progress.analysisPhase == .incomplete && progress.failedCount > 0
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
    /// Invalidates UI publications from a superseded classification pass. Task
    /// cancellation is cooperative, so cancellation alone cannot prevent a batch
    /// already hopping back to the main actor from landing on a newer snapshot.
    @ObservationIgnored private var classificationGeneration = 0

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
        case .sceneBecameActive:
            // Background classification mutates the shared category store, not
            // this view model. Rebuild from that durable truth whenever the scene
            // returns instead of waiting for a PhotoKit library-change event.
            guard state.phase == .loaded else { return }
            refreshFlow()
        case .grantAccess:
            guard state.phase == .primingAccess else { return }
            loadFlow()
        case .retry:
            loadFlow()
        case .retryAnalysis:
            guard state.phase == .loaded else { return }
            refreshFlow()
        case .openSystemSettings:
            router.openSystemSettings()
        case .addMorePhotos:
            router.presentLimitedLibraryPicker()
        }
    }

    private func loadFlow() {
        run(.load) { [weak self] in
            guard let self else { return }
            self.invalidateClassificationPass()
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
        let generation = invalidateClassificationPass()
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
        progress.failedCount = 0
        classifyFlow(
            pending,
            startingFrom: progress.classifiedCount,
            generation: generation
        )
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

    // `base` is how many screenshots the cache already covered. Only successful
    // verdicts advance the count; failed attempts stay pending across retries.
    //
    // The stream is consumed off the main actor and published on a fixed tick.
    // Applying every result as it lands put one `@Observable` mutation — and so
    // one full re-render of the hero metric and the glass summary card — on the
    // main thread per screenshot, for the length of a cold pass. That is what
    // made the toolbar and Start Triage feel unresponsive on first launch.
    private func classifyFlow(
        _ screenshots: [Screenshot],
        startingFrom base: Int,
        generation: Int
    ) {
        guard !screenshots.isEmpty else {
            progress.startedAt = nil
            progress.analysisPhase = .complete
            return
        }
        progress.startedAt = .now
        progress.startedFrom = base
        progress.analysisPhase = .running
        progress.failedCount = 0

        let classifyLibrary = classifyLibrary
        let sizes = sizes
        let interval = Self.progressPublishInterval
        let retryDelays = Self.retryDelays
        let maximumAttempts = Self.maximumClassificationAttempts
        tasks[.classify] = Task.detached(priority: .utility) { [weak self] in
            var pending = screenshots
            var resolved = 0

            for attemptIndex in 0..<maximumAttempts {
                var unresolvedIDs = Set(pending.map(\.id))
                var batch = OverviewSummary()
                var lastPublish = ContinuousClock.now

                for await item in classifyLibrary.execute(pending) {
                    guard !Task.isCancelled else { return }
                    if let id = item.id, let classification = item.classification {
                        unresolvedIDs.remove(id)
                        resolved += 1
                        batch.add(bytes: sizes[id] ?? 0, disposition: classification.disposition)
                    }

                    let now = ContinuousClock.now
                    guard now - lastPublish >= interval else { continue }
                    lastPublish = now
                    let published = batch
                    batch = OverviewSummary()
                    await self?.publish(
                        published,
                        classifiedCount: base + resolved,
                        generation: generation
                    )
                }

                await self?.publish(
                    batch,
                    classifiedCount: base + resolved,
                    generation: generation
                )

                // Failed, cancelled, or non-yielding work remains pending.
                // Counting it as classified is the bug that made Overview hide
                // its analyzing state with only a partial MB total.
                let retry = pending.filter { unresolvedIDs.contains($0.id) }
                guard !retry.isEmpty else {
                    await self?.finishClassifying(
                        failedCount: 0,
                        classifiedCount: base + resolved,
                        generation: generation
                    )
                    return
                }

                pending = retry
                guard attemptIndex < retryDelays.count else { break }
                do {
                    try await Task.sleep(for: retryDelays[attemptIndex])
                } catch {
                    return
                }
            }

            await self?.finishClassifying(
                failedCount: pending.count,
                classifiedCount: base + resolved,
                generation: generation
            )
        }
    }

    /// Folds one tick's worth of results into the screen's state.
    private func publish(
        _ batch: OverviewSummary,
        classifiedCount: Int,
        generation: Int
    ) {
        guard classificationGeneration == generation else { return }
        progress.summary.merge(batch)
        progress.classifiedCount = classifiedCount
    }

    private func finishClassifying(
        failedCount: Int,
        classifiedCount: Int,
        generation: Int
    ) {
        guard classificationGeneration == generation else { return }
        progress.classifiedCount = classifiedCount
        progress.failedCount = failedCount
        progress.startedAt = nil
        progress.analysisPhase = failedCount == 0 ? .complete : .incomplete
    }

    /// How often a running pass is allowed to move the screen. Slow enough that
    /// the summary card is not re-rendered per screenshot, fast enough that the
    /// hero figure still reads as live.
    private static let progressPublishInterval: Duration = .milliseconds(250)
    private static let retryDelays: [Duration] = [.milliseconds(250), .seconds(1)]
    private static let maximumClassificationAttempts = retryDelays.count + 1

    /// Cancels the consumer and retires every publication already queued by it.
    /// Returns the token the replacement pass must use.
    @discardableResult
    private func invalidateClassificationPass() -> Int {
        tasks[.classify]?.cancel()
        tasks[.classify] = nil
        classificationGeneration += 1
        return classificationGeneration
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
        progress.analysisPhase = .complete
    }
    #endif
}
