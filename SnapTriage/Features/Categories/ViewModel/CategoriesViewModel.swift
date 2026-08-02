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

        var groups: [CategoryGroup] { breakdown.groups }
    }

    enum Input {
        case onAppear
        case retry
    }

    private(set) var state = State()

    private let loadBreakdown: LoadCategoryBreakdownUseCase

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(loadBreakdown: LoadCategoryBreakdownUseCase) {
        self.loadBreakdown = loadBreakdown
    }

    func send(_ input: Input) {
        switch input {
        case .onAppear:
            // Reload every visit: swipes made in the deck since the last look
            // shrink these groups, verdicts applied inside a category retire
            // them, and the classifier keeps filling them in.
            loadFlow()
        case .retry:
            loadFlow()
        }
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
