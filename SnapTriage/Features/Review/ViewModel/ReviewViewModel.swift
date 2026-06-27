//
//  ReviewViewModel.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ReviewViewModel {

    enum Phase: Equatable { case idle, loading, loaded, failed }

    struct State: Equatable {
        var phase: Phase = .idle
        var authorization: PhotoLibraryAuthorization = .notDetermined
        var items: [ReviewItem] = []
        var selectedIDs: Set<Screenshot.ID> = []
        var errorMessage: String?
        /// True while a delete is in flight, so the view can disable the action.
        var isDeleting = false

        var selectedCount: Int { selectedIDs.count }

        /// Bytes freed if the current selection is deleted.
        var reclaimableBytes: Int {
            items.reduce(0) { $0 + (selectedIDs.contains($1.id) ? $1.byteSize : 0) }
        }

        var hasSelection: Bool { !selectedIDs.isEmpty }
    }

    enum Input {
        case onAppear
        case retry
        case toggle(Screenshot.ID)
        case deleteSelected
        case openSettings
        case clearError
    }

    private(set) var state = State()

    private let requestAccess: RequestPhotoAccessUseCase
    private let loadItems: LoadReviewItemsUseCase
    private let deleteScreenshots: DeleteScreenshotsUseCase
    private let imageLoader: PhotoLibraryService
    private let router: ReviewRouter

    private enum TaskKind { case load, delete }
    @ObservationIgnored private var tasks: [TaskKind: Task<Void, Never>] = [:]

    init(
        requestAccess: RequestPhotoAccessUseCase,
        loadItems: LoadReviewItemsUseCase,
        deleteScreenshots: DeleteScreenshotsUseCase,
        imageLoader: PhotoLibraryService,
        router: ReviewRouter
    ) {
        self.requestAccess = requestAccess
        self.loadItems = loadItems
        self.deleteScreenshots = deleteScreenshots
        self.imageLoader = imageLoader
        self.router = router
    }

    func send(_ input: Input) {
        switch input {
        case .onAppear:
            if state.phase == .idle { loadFlow() }
        case .retry:
            loadFlow()
        case .toggle(let id):
            toggle(id)
        case .deleteSelected:
            deleteFlow()
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
            if Task.isCancelled { return }
            self.state.authorization = authorization

            guard authorization.canAccessLibrary else {
                self.state.errorMessage = self.presentAuth(authorization)
                self.state.phase = .failed
                return
            }

            do {
                let items = try await self.loadItems.execute()
                try Task.checkCancellation()
                self.state.items = items
                self.state.selectedIDs = Set(items.map(\.id))   // everything pre-selected
                self.state.phase = .loaded
            } catch is CancellationError {
                // superseded by a newer load
            } catch {
                self.state.errorMessage = self.present(error)
                self.state.phase = .failed
            }
        }
    }

    private func toggle(_ id: Screenshot.ID) {
        if state.selectedIDs.contains(id) {
            state.selectedIDs.remove(id)
        } else {
            state.selectedIDs.insert(id)
        }
    }

    private func deleteFlow() {
        let ids = Array(state.selectedIDs)
        guard !ids.isEmpty, !state.isDeleting else { return }

        run(.delete) { [weak self] in
            guard let self else { return }
            self.state.isDeleting = true
            defer { self.state.isDeleting = false }
            do {
                try await self.deleteScreenshots.execute(ids)
                let deleted = Set(ids)
                self.state.items.removeAll { deleted.contains($0.id) }
                self.state.selectedIDs.subtract(deleted)
            } catch TriageError.deletionCancelled {
                // User backed out of the system sheet — leave the selection intact.
            } catch is CancellationError {
                // superseded
            } catch {
                self.state.errorMessage = self.present(error)
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
        case TriageError.deletionFailed:        return Strings.Review.deletionFailed
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
    func seedForPreview(_ items: [ReviewItem]) {
        state.phase = .loaded
        state.authorization = .authorized
        state.items = items
        state.selectedIDs = Set(items.map(\.id))
    }
    #endif
}
