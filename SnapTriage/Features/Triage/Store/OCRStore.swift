//
//  OCRStore.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation

protocol OCRStore: Sendable {
    func result(for id: Screenshot.ID) async -> OCRResult?
    func save(_ result: OCRResult) async
    /// Drops the results for screenshots that no longer exist, e.g. after
    /// Review deletes them.
    func remove(_ ids: [Screenshot.ID]) async
}

actor InMemoryOCRStore: OCRStore {

    private var cache: [Screenshot.ID: OCRResult] = [:]

    func result(for id: Screenshot.ID) -> OCRResult? {
        cache[id]
    }

    func save(_ result: OCRResult) {
        cache[result.screenshotID] = result
    }

    func remove(_ ids: [Screenshot.ID]) {
        ids.forEach { cache[$0] = nil }
    }
}

