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
    /// Drops the verdicts for screenshots that no longer exist, e.g. after
    /// Review deletes them.
    func remove(_ ids: [Screenshot.ID])
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

    func remove(_ ids: [Screenshot.ID]) {
        cache.withLock { dict in ids.forEach { dict[$0] = nil } }
    }

    func removeAll() {
        cache.withLock { $0.removeAll() }
    }
}

/// Disk-backed store so swipe verdicts survive relaunch. Verdicts are user
/// intent, so the file lives in Application Support, not Caches.
final class FileBackedTriageDecisionStore: TriageDecisionStore {

    private let storage: PersistedDictionary<TriageDecision>

    init(directory: URL) {
        storage = PersistedDictionary(name: "triage-decisions", directory: directory)
    }

    func decision(for id: Screenshot.ID) -> TriageDecision? {
        storage[id]
    }

    func save(_ decision: TriageDecision, for id: Screenshot.ID) {
        storage.set(decision, for: id)
    }

    func allDecisions() -> [Screenshot.ID: TriageDecision] {
        storage.snapshot()
    }

    func remove(_ ids: [Screenshot.ID]) {
        storage.remove(ids)
    }

    func removeAll() {
        storage.removeAll()
    }

    func flush() {
        storage.flush()
    }
}
