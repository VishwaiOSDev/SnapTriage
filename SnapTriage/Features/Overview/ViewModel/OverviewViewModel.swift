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
    private let router: OverviewRouter

    private enum TaskKind { case load, classify }
    @ObservationIgnored private var tasks: [TaskKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var sizes: [Screenshot.ID: Int] = [:]

    init(
        requestAccess: RequestPhotoAccessUseCase,
        loadScreenshots: LoadScreenshotsUseCase,
        classifyLibrary: ClassifyLibraryUseCase,
        router: OverviewRouter
    ) {
        self.requestAccess = requestAccess
        self.loadScreenshots = loadScreenshots
        self.classifyLibrary = classifyLibrary
        self.router = router
    }

    func send(_ input: Input) {
        switch input {
        case .onAppear:
            if state.phase == .idle { loadFlow() }
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
                self.sizes = Dictionary(
                    screenshots.map { ($0.id, $0.byteSize) },
                    uniquingKeysWith: { first, _ in first }
                )
                self.state.summary.totalCount = screenshots.count
                self.state.phase = .loaded
                self.classifyFlow(screenshots)
            } catch is CancellationError {
                // superseded by a newer load
            } catch {
                self.state.errorMessage = self.present(error)
                self.state.phase = .failed
            }
        }
    }

    private func classifyFlow(_ screenshots: [Screenshot]) {
        guard !screenshots.isEmpty else { return }
        run(.classify) { [weak self] in
            guard let self else { return }
            for await progress in self.classifyLibrary.execute(screenshots) {
                if Task.isCancelled { break }
                self.state.classifiedCount = progress.completed
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
