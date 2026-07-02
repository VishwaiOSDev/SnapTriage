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

    enum Phase: Equatable { case idle, loading, loaded, failed }

    struct State: Equatable {
        var phase: Phase = .idle
        var summary: OverviewSummary = .empty
        var classifiedCount = 0
        var errorMessage: String?
        var authorization: PhotoLibraryAuthorization = .notDetermined
        var features: [FeatureHighlight] = FeatureHighlight.defaults

        var isClassifying: Bool {
            phase == .loaded && summary.totalCount > 0 && classifiedCount < summary.totalCount
        }
    }

    enum Input {
        case onAppear
        case retry
        case openSettings
        case selectFeature(FeatureHighlight.ID)
    }

    private(set) var state = State()

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
            if state.phase == .idle {
                loadFlow()
                observeChanges()
            }
        case .retry:
            loadFlow()
        case .openSettings:
            router.openSettings()
        case .selectFeature:
            break
        }
    }

    private func loadFlow() {
        run(.load) { [weak self] in
            guard let self else { return }
            self.tasks[.classify]?.cancel()
            self.state.phase = .loading
            self.state.errorMessage = nil
            self.state.summary = .empty
            self.state.classifiedCount = 0

            let authorization = await self.requestAccess.execute()
            if Task.isCancelled { return }
            self.state.authorization = authorization

            guard authorization.canAccessLibrary else {
                self.state.errorMessage = self.presentAuth(authorization)
                self.state.phase = .failed
                return
            }

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

        let cached = await classifyLibrary.cachedCategories()
        if Task.isCancelled { return }
        var summary = OverviewSummary()
        summary.totalCount = screenshots.count
        var pending: [Screenshot] = []
        for screenshot in screenshots {
            if let category = cached[screenshot.id] {
                summary.add(bytes: screenshot.byteSize, disposition: category.disposition)
            } else {
                pending.append(screenshot)
            }
        }
        state.summary = summary
        state.classifiedCount = screenshots.count - pending.count
        classifyFlow(pending, startingFrom: state.classifiedCount)
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
        guard !screenshots.isEmpty else { return }
        run(.classify) { [weak self] in
            guard let self else { return }
            for await progress in self.classifyLibrary.execute(screenshots) {
                if Task.isCancelled { break }
                self.state.classifiedCount = base + progress.completed
                guard let id = progress.id else { continue }
                if let category = progress.category {
                    self.state.summary.add(
                        bytes: self.sizes[id] ?? 0,
                        disposition: category.disposition
                    )
                } else {
                    self.state.summary.unknownCount += 1
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
    func seedForPreview(_ summary: OverviewSummary) {
        state.phase = .loaded
        state.summary = summary
        state.classifiedCount = summary.totalCount
    }
    #endif
}
