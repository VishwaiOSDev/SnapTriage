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
}

actor InMemoryCategoryStore: CategoryStore {

    private var cache: [Screenshot.ID: ScreenshotCategory] = [:]

    func category(for id: Screenshot.ID) -> ScreenshotCategory? {
        cache[id]
    }

    func save(_ category: ScreenshotCategory, for id: Screenshot.ID) {
        cache[id] = category
    }
}
