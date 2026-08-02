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
        /// True while a reload runs *over* content that is already on screen.
        /// Distinct from `.loading`, which means there is nothing to show yet.
        var isRefreshing = false

        var selectedCount: Int { selectedIDs.count }

        /// Bytes freed if the current selection is deleted.
        var reclaimableBytes: Int {
            items.reduce(0) { $0 + (selectedIDs.contains($1.id) ? $1.byteSize : 0) }
        }

        var hasSelection: Bool { !selectedIDs.isEmpty }

        /// Screenshots the user swiped left. These arrive selected.
        var markedItems: [ReviewItem] { items.filter { $0.source == .userMarked } }

        /// Screenshots the user has not ruled on. In the triage inbox these are
        /// the classifier's disposable guesses; in a category scope they are the
        /// rest of the bucket. Either way they arrive unselected: the user has
        /// never seen them, so deleting them cannot be the default.
        var suggestedItems: [ReviewItem] { items.filter { $0.source == .suggested } }

        var suggestedBytes: Int { suggestedItems.reduce(0) { $0 + $1.byteSize } }

        var totalBytes: Int { items.reduce(0) { $0 + $1.byteSize } }

        var areAllSuggestionsSelected: Bool {
            let suggested = suggestedItems
            return !suggested.isEmpty && suggested.allSatisfy { selectedIDs.contains($0.id) }
        }

        var areAllSelected: Bool {
            !items.isEmpty && selectedIDs.count == items.count
        }
    }

    enum Input {
        case onAppear
        case retry
        case toggle(Screenshot.ID)
        case toggleAllSuggestions
        case toggleSelectAll
        case deleteSelected
        case openSystemSettings
        case clearError
    }

    private(set) var state = State()

    /// Which screenshots this instance answers for. Fixed at construction: a
    /// scope change is a different screen, not a different state.
    let scope: ReviewScope

    private let requestAccess: RequestPhotoAccessUseCase
    private let loadItems: LoadReviewItemsUseCase
    private let deleteScreenshots: DeleteScreenshotsUseCase
    private let pruneRecords: PruneScreenshotRecordsUseCase
    private let imageLoader: PhotoLibraryService
    private let router: ReviewRouter

    private enum TaskKind { case load, delete }
    @ObservationIgnored private var tasks: [TaskKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var loadGeneration = 0

    init(
        scope: ReviewScope = .triage,
        requestAccess: RequestPhotoAccessUseCase,
        loadItems: LoadReviewItemsUseCase,
        deleteScreenshots: DeleteScreenshotsUseCase,
        pruneRecords: PruneScreenshotRecordsUseCase,
        imageLoader: PhotoLibraryService,
        router: ReviewRouter
    ) {
        self.scope = scope
        self.requestAccess = requestAccess
        self.loadItems = loadItems
        self.deleteScreenshots = deleteScreenshots
        self.pruneRecords = pruneRecords
        self.imageLoader = imageLoader
        self.router = router
    }

    func send(_ input: Input) {
        switch input {
        case .onAppear:
            // Reload every visit: triage swipes made since the last look must
            // land here, and the classification pass is cache-first anyway.
            if !state.isDeleting { loadFlow() }
        case .retry:
            loadFlow()
        case .toggle(let id):
            toggle(id)
        case .toggleAllSuggestions:
            toggleAllSuggestions()
        case .toggleSelectAll:
            toggleSelectAll()
        case .deleteSelected:
            deleteFlow()
        case .openSystemSettings:
            router.openSystemSettings()
        case .clearError:
            state.errorMessage = nil
        }
    }

    // Transient read for grid cells, not domain state, so bypasses send.
    func thumbnail(for id: Screenshot.ID, targetSize: CGSize) async -> UIImage? {
        await imageLoader.thumbnail(for: id, targetSize: targetSize, mode: .fill)
    }

    private func loadFlow() {
        loadGeneration &+= 1
        let generation = loadGeneration
        run(.load) { [weak self] in
            guard let self else { return }
            // A revisit re-runs this load. Blanking the grid to a spinner every
            // time cost the user their scroll position and their place in the
            // selection, so a reload over existing content refreshes in place.
            if self.state.items.isEmpty {
                self.state.phase = .loading
            } else {
                self.state.isRefreshing = true
            }
            // A superseded load must not clear the flag a newer one just set.
            defer { if self.loadGeneration == generation { self.state.isRefreshing = false } }
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
                let items = try await self.loadItems.execute(scope: self.scope)
                try Task.checkCancellation()
                // Two rules compose here. Only verdicts the user actually gave
                // are ever armed for deletion — a classifier suggestion has to
                // be opted into, so one heuristic false positive can never be
                // deleted by a user who just taps the red button. And only
                // items new since the last load get their default selection;
                // anything already on screen keeps whatever the user chose, so
                // a manual deselection survives a revisit instead of being
                // silently re-armed.
                let knownIDs = Set(self.state.items.map(\.id))
                let currentIDs = Set(items.map(\.id))
                let newlyMarkedIDs = Set(
                    items.lazy
                        .filter { $0.source == .userMarked && !knownIDs.contains($0.id) }
                        .map(\.id)
                )
                self.state.selectedIDs = self.state.selectedIDs
                    .intersection(currentIDs)
                    .union(newlyMarkedIDs)
                self.state.items = items
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

    /// One control for the whole suggestion section: arms every suggestion, or
    /// clears them all if they are already armed.
    private func toggleAllSuggestions() {
        let ids = state.suggestedItems.map(\.id)
        guard !ids.isEmpty else { return }
        if state.areAllSuggestionsSelected {
            state.selectedIDs.subtract(ids)
        } else {
            state.selectedIDs.formUnion(ids)
        }
    }

    /// The screen-level control: arms everything, or clears the whole selection
    /// if it is already armed. Suggestions are only ever included by this kind
    /// of explicit tap, never by a default.
    private func toggleSelectAll() {
        guard !state.items.isEmpty else { return }
        if state.areAllSelected {
            state.selectedIDs.removeAll()
        } else {
            state.selectedIDs = Set(state.items.map(\.id))
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
                await self.pruneRecords.execute(ids)
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
        state.selectedIDs = Set(items.filter { $0.source == .userMarked }.map(\.id))
    }
    #endif
}
