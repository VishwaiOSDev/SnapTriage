//
//  TriageDecisionStore.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/07/26.
//

import Foundation
import Synchronization

/// Synchronous by design: a swipe must be in the store before the deck
/// advances, so any Review load that starts afterwards observes it.
protocol TriageDecisionStore: Sendable {
    func decision(for id: Screenshot.ID) -> TriageDecision?
    func save(_ decision: TriageDecision, for id: Screenshot.ID)
    /// Every decision recorded so far, keyed by screenshot id. The Review
    /// feature reads this to fold the user's swipes into its deletion set.
    func allDecisions() -> [Screenshot.ID: TriageDecision]
    /// Forgets every verdict; backs "Start Over" on the triage finished screen.
    func removeAll()
}

final class InMemoryTriageDecisionStore: TriageDecisionStore {

    private let cache = Mutex<[Screenshot.ID: TriageDecision]>([:])

    func decision(for id: Screenshot.ID) -> TriageDecision? {
        cache.withLock { $0[id] }
    }

    func save(_ decision: TriageDecision, for id: Screenshot.ID) {
        cache.withLock { $0[id] = decision }
    }

    func allDecisions() -> [Screenshot.ID: TriageDecision] {
        cache.withLock { $0 }
    }

    func removeAll() {
        cache.withLock { $0.removeAll() }
    }
}
