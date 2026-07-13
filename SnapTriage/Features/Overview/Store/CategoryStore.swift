//
//  CategoryStore.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

/// Persists the full ``ScreenshotClassification`` — category, confidence, source,
/// and evidence — not merely the category. Storing confidence is what lets
/// retention stay correct across relaunch: a low-confidence verdict reloads as
/// `needsReview`, never as a safe deletion candidate.
protocol CategoryStore: Sendable {
    func classification(for id: Screenshot.ID) async -> ScreenshotClassification?
    func save(_ classification: ScreenshotClassification, for id: Screenshot.ID) async
    /// Every classification cached so far, keyed by screenshot id. Overview and
    /// Review read this to build their summaries without re-running the pipeline.
    func allClassifications() async -> [Screenshot.ID: ScreenshotClassification]
    /// Drops the classifications for screenshots that no longer exist, e.g. after
    /// Review deletes them.
    func remove(_ ids: [Screenshot.ID]) async
}

actor InMemoryCategoryStore: CategoryStore {

    private var cache: [Screenshot.ID: ScreenshotClassification] = [:]

    func classification(for id: Screenshot.ID) -> ScreenshotClassification? {
        cache[id]
    }

    func save(_ classification: ScreenshotClassification, for id: Screenshot.ID) {
        cache[id] = classification
    }

    func allClassifications() -> [Screenshot.ID: ScreenshotClassification] {
        cache
    }

    func remove(_ ids: [Screenshot.ID]) {
        ids.forEach { cache[$0] = nil }
    }
}

/// Disk-backed store so classifications survive relaunch. Recomputable, so the
/// file lives in Caches — if the system purges it the pipeline just re-runs.
final class FileBackedCategoryStore: CategoryStore {

    /// Bump when the classifier (rules, cascade, prompt, or the stored schema)
    /// changes: cached verdicts from the old classifier are stale, and a new file
    /// name makes the whole library re-classify on next launch. User decisions
    /// live in a separate store and are never touched by this migration.
    ///
    /// v6: cheap-first cascade; stores `ScreenshotClassification` (was a bare
    /// `ScreenshotCategory`), so the schema changed too.
    private static let classifierVersion = 6

    private let storage: PersistedDictionary<ScreenshotClassification>

    init(directory: URL) {
        storage = PersistedDictionary(
            name: "screenshot-classifications-v\(Self.classifierVersion)",
            directory: directory
        )
    }

    func classification(for id: Screenshot.ID) -> ScreenshotClassification? {
        storage[id]
    }

    func save(_ classification: ScreenshotClassification, for id: Screenshot.ID) {
        storage.set(classification, for: id)
    }

    func allClassifications() -> [Screenshot.ID: ScreenshotClassification] {
        storage.snapshot()
    }

    func remove(_ ids: [Screenshot.ID]) {
        storage.remove(ids)
    }

    func flush() {
        storage.flush()
    }
}
