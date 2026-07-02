//
//  CategoryStore.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

protocol CategoryStore: Sendable {
    func category(for id: Screenshot.ID) async -> ScreenshotCategory?
    func save(_ category: ScreenshotCategory, for id: Screenshot.ID) async
    /// Every category cached so far, keyed by screenshot id. The Review feature
    /// reads this to build the "safe to delete" set without re-running the pipeline.
    func allCategories() async -> [Screenshot.ID: ScreenshotCategory]
    /// Drops the categories for screenshots that no longer exist, e.g. after
    /// Review deletes them.
    func remove(_ ids: [Screenshot.ID]) async
}

actor InMemoryCategoryStore: CategoryStore {

    private var cache: [Screenshot.ID: ScreenshotCategory] = [:]

    func category(for id: Screenshot.ID) -> ScreenshotCategory? {
        cache[id]
    }

    func save(_ category: ScreenshotCategory, for id: Screenshot.ID) {
        cache[id] = category
    }

    func allCategories() -> [Screenshot.ID: ScreenshotCategory] {
        cache
    }

    func remove(_ ids: [Screenshot.ID]) {
        ids.forEach { cache[$0] = nil }
    }
}

