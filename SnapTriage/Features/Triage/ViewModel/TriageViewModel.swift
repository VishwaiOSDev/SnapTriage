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

    struct State: Equatable {
        var authorization: PhotoLibraryAuthorization = .notDetermined
        var screenshots: [Screenshot] = []
        var phase: Phase = .idle
        var errorMessage: String?
    }

    enum Input {
        case onAppear
        case retry
        case openSettings
        case clearError
    }

    private(set) var state = State()

    private let requestAccess: RequestPhotoAccessUseCase
    private let loadScreenshots: LoadScreenshotsUseCase
    private let imageLoader: PhotoLibraryService
    private let router: TriageRouter

    private enum TaskKind { case load }
    @ObservationIgnored private var tasks: [TaskKind: Task<Void, Never>] = [:]

    init(
        requestAccess: RequestPhotoAccessUseCase,
        loadScreenshots: LoadScreenshotsUseCase,
        imageLoader: PhotoLibraryService,
        router: TriageRouter
    ) {
        self.requestAccess = requestAccess
        self.loadScreenshots = loadScreenshots
        self.imageLoader = imageLoader
        self.router = router
    }

    func send(_ input: Input) {
        switch input {
        case .onAppear, .retry:
            loadFlow()
        case .openSettings:
            router.openSettings()
        case .clearError:
            state.errorMessage = nil
        }
    }

    // Transient read for grid cells, not domain state, so bypasses send.
    func thumbnail(for id: Screenshot.ID, targetSize: CGSize) async -> UIImage? {
        await imageLoader.thumbnail(for: id, targetSize: targetSize)
    }

    private func loadFlow() {
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
                self.state.screenshots = screenshots
                self.state.phase = .loaded
            } catch is CancellationError {
                // superseded by newer load
            } catch {
                self.state.errorMessage = self.present(error)
                self.state.phase = .failed
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
}
