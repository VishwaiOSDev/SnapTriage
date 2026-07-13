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

/// Disk-backed store so OCR transcripts survive relaunch. Recomputable, so the
/// file lives in Caches — if the system purges it the pipeline just re-runs.
final class FileBackedOCRStore: OCRStore {

    /// OCR ordering feeds the classifier. Bump when recognition settings or reading-order logic
    /// changes so cached transcripts do not preserve stale structure.
    /// v3 adds official-ID vocabulary to Vision's language-correction hints.
    private static let ocrVersion = 3

    private let storage: PersistedDictionary<OCRResult>

    init(directory: URL) {
        storage = PersistedDictionary(name: "ocr-results-v\(Self.ocrVersion)", directory: directory)
    }

    func result(for id: Screenshot.ID) -> OCRResult? {
        storage[id]
    }

    func save(_ result: OCRResult) {
        storage.set(result, for: result.screenshotID)
    }

    func remove(_ ids: [Screenshot.ID]) {
        storage.remove(ids)
    }

    func flush() {
        storage.flush()
    }
}
