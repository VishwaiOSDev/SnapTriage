//
//  ClassifyLibraryUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

/// Classifies a screenshot library with bounded concurrency and streams each
/// result as it lands. Every app feature receives a use case backed by the same
/// ``LibraryClassificationEngine`` so overlapping Overview, Triage, Review, and
/// background requests join one per-screenshot operation instead of repeating
/// OCR and model inference.
struct ClassifyLibraryUseCase: Sendable {

    enum Resolution: Sendable, Equatable {
        case cached
        case classified
        case failed
    }

    struct Progress: Sendable {
        let id: Screenshot.ID?
        let classification: ScreenshotClassification?
        let resolution: Resolution?
        let completed: Int
        let total: Int
    }

    private let engine: LibraryClassificationEngine
    private let cheapConcurrency = 4

    init(
        recognizeText: RecognizeScreenshotTextUseCase,
        categorize: CategorizeScreenshotUseCase,
        store: CategoryStore
    ) {
        engine = LibraryClassificationEngine(
            recognizeText: recognizeText,
            categorize: categorize,
            store: store
        )
    }

    init(engine: LibraryClassificationEngine) {
        self.engine = engine
    }

    func prewarm() {
        engine.prewarm()
    }

    func cachedClassifications() async -> [Screenshot.ID: ScreenshotClassification] {
        await engine.cachedClassifications()
    }

    /// Makes every OCR and classification completed so far durable before a
    /// background assertion or BGProcessingTask is released.
    func flush() async {
        await engine.flush()
    }

    /// Drops every cached verdict so the next pass re-classifies from scratch.
    func clearCache() async {
        await engine.clearCache()
    }

    func execute(_ screenshots: [Screenshot]) -> AsyncStream<Progress> {
        AsyncStream { continuation in
            let engine = engine
            let cheapConcurrency = cheapConcurrency
            let task = Task(priority: .utility) {
                engine.prewarm()
                let total = screenshots.count
                var completed = 0
                var index = 0

                await withTaskGroup(of: LibraryClassificationEngine.Attempt?.self) { group in
                    func addNext() {
                        guard index < screenshots.count, !Task.isCancelled else { return }
                        let shot = screenshots[index]
                        index += 1
                        group.addTask(priority: .utility) {
                            let attempts = await engine.attempts(for: shot)
                            for await attempt in attempts {
                                return attempt
                            }
                            return nil
                        }
                    }

                    for _ in 0..<min(cheapConcurrency, screenshots.count) { addNext() }

                    for await attempt in group {
                        guard !Task.isCancelled else { break }
                        guard let attempt else { continue }
                        completed += 1
                        continuation.yield(
                            Progress(
                                id: attempt.id,
                                classification: attempt.classification,
                                resolution: attempt.resolution,
                                completed: completed,
                                total: total
                            )
                        )
                        addNext()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
