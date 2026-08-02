//
//  CategoriesViewModel.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class CategoriesViewModel {

    enum Phase: Equatable { case idle, loading, loaded, failed }

    struct State: Equatable {
        var phase: Phase = .idle
        var breakdown: CategoryBreakdown = .empty
        var errorMessage: String?
        /// The last bulk verdict, kept only until the next one replaces it.
        /// Hundreds of screenshots change hands in one tap here; a single step
        /// back is the difference between a shortcut and a trap.
        var lastReceipt: BulkTriageReceipt?

        var groups: [CategoryGroup] { breakdown.groups }
        var canUndo: Bool { lastReceipt != nil }
    }

    enum Input {
        case onAppear
        case retry
        case apply(TriageDecision, CategoryGroup)
        case undoLast
    }

    private(set) var state = State()

    private let loadBreakdown: LoadCategoryBreakdownUseCase
    private let applyBulk: ApplyBulkTriageUseCase
    private let revertBulk: RevertBulkTriageUseCase

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(
        loadBreakdown: LoadCategoryBreakdownUseCase,
        applyBulk: ApplyBulkTriageUseCase,
        revertBulk: RevertBulkTriageUseCase
    ) {
        self.loadBreakdown = loadBreakdown
        self.applyBulk = applyBulk
        self.revertBulk = revertBulk
    }

    func send(_ input: Input) {
        switch input {
        case .onAppear:
            // Reload every visit: swipes made in the deck since the last look
            // shrink these groups, and the classifier keeps filling them in.
            loadFlow()
        case .retry:
            loadFlow()
        case .apply(let decision, let group):
            apply(decision, to: group)
        case .undoLast:
            undoLast()
        }
    }

    private func apply(_ decision: TriageDecision, to group: CategoryGroup) {
        guard !group.ids.isEmpty else { return }
        state.lastReceipt = applyBulk.execute(decision, for: group.category, ids: group.ids)
        loadFlow()
    }

    private func undoLast() {
        guard let receipt = state.lastReceipt else { return }
        revertBulk.execute(receipt)
        state.lastReceipt = nil
        loadFlow()
    }

    private func loadFlow() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            if self.state.phase == .idle { self.state.phase = .loading }
            self.state.errorMessage = nil
            do {
                let breakdown = try await self.loadBreakdown.execute()
                try Task.checkCancellation()
                self.state.breakdown = breakdown
                self.state.phase = .loaded
            } catch is CancellationError {
                // superseded by a newer load
            } catch {
                self.state.errorMessage = self.present(error)
                self.state.phase = .failed
            }
        }
    }

    private func present(_ error: Error) -> String {
        switch error {
        case TriageError.photoAccessDenied:     return Strings.Error.accessDenied
        case TriageError.photoAccessRestricted: return Strings.Error.accessRestricted
        default:                                return Strings.Error.generic
        }
    }

    deinit {
        loadTask?.cancel()
    }

    #if DEBUG
    func seedForPreview(_ breakdown: CategoryBreakdown) {
        state.phase = .loaded
        state.breakdown = breakdown
    }
    #endif
}
