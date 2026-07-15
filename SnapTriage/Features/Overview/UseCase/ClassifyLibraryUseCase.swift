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

    #if DEBUG
    func clearCache() async {
        await engine.clearCache()
    }
    #endif

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

/// Process-wide, per-screenshot single-flight owner. A caller subscribes to an
/// attempt stream; if another feature already started that screenshot, both get
/// the same result. When the last subscriber goes away the underlying operation
/// is cancelled, making BGTask expiration cooperative without disrupting work
/// still observed by a foreground feature.
actor LibraryClassificationEngine {

    struct Attempt: Sendable {
        let id: Screenshot.ID
        let classification: ScreenshotClassification?
        let resolution: ClassifyLibraryUseCase.Resolution
    }

    private struct InFlight {
        let token: UUID
        let task: Task<Void, Never>
        var subscribers: [UUID: AsyncStream<Attempt>.Continuation]
    }

    private let recognizeText: RecognizeScreenshotTextUseCase
    private let categorize: CategorizeScreenshotUseCase
    private let store: CategoryStore
    private var inFlight: [Screenshot.ID: InFlight] = [:]

    init(
        recognizeText: RecognizeScreenshotTextUseCase,
        categorize: CategorizeScreenshotUseCase,
        store: CategoryStore
    ) {
        self.recognizeText = recognizeText
        self.categorize = categorize
        self.store = store
    }

    nonisolated func prewarm() {
        categorize.prewarm()
    }

    func cachedClassifications() async -> [Screenshot.ID: ScreenshotClassification] {
        await store.allClassifications()
    }

    func flush() async {
        await recognizeText.flush()
        await store.flushPendingWrites()
    }

    func attempts(for screenshot: Screenshot) async -> AsyncStream<Attempt> {
        if let cached = await store.classification(for: screenshot.id) {
            return AsyncStream { continuation in
                continuation.yield(Attempt(
                    id: screenshot.id,
                    classification: cached.asCached(),
                    resolution: .cached
                ))
                continuation.finish()
            }
        }

        let subscriberID = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(subscriberID, from: screenshot.id) }
            }

            if var existing = inFlight[screenshot.id] {
                existing.subscribers[subscriberID] = continuation
                inFlight[screenshot.id] = existing
                return
            }

            let token = UUID()
            let recognizeText = recognizeText
            let categorize = categorize
            let store = store
            let task = Task.detached(priority: .utility) { [weak self] in
                let attempt = await Self.perform(
                    screenshot,
                    recognizeText: recognizeText,
                    categorize: categorize,
                    store: store
                )
                await self?.finish(attempt, token: token)
            }
            inFlight[screenshot.id] = InFlight(
                token: token,
                task: task,
                subscribers: [subscriberID: continuation]
            )
        }
    }

    #if DEBUG
    func clearCache() async {
        let running = inFlight.values.map(\.task)
        inFlight.removeAll()
        running.forEach { $0.cancel() }
        await store.removeAll()
    }
    #endif

    private static func perform(
        _ screenshot: Screenshot,
        recognizeText: RecognizeScreenshotTextUseCase,
        categorize: CategorizeScreenshotUseCase,
        store: CategoryStore
    ) async -> Attempt {
        guard !Task.isCancelled else {
            return Attempt(id: screenshot.id, classification: nil, resolution: .failed)
        }

        if let cached = await store.classification(for: screenshot.id) {
            return Attempt(
                id: screenshot.id,
                classification: cached.asCached(),
                resolution: .cached
            )
        }

        do {
            let recognized = try await recognizeText.executeWithSourceImage(screenshotID: screenshot.id)
            try Task.checkCancellation()
            let classification = await categorize.execute(
                recognized.result,
                sourceImage: recognized.sourceImage
            )
            try Task.checkCancellation()
            await store.save(classification, for: screenshot.id)
            return Attempt(id: screenshot.id, classification: classification, resolution: .classified)
        } catch {
            return Attempt(id: screenshot.id, classification: nil, resolution: .failed)
        }
    }

    private func finish(_ attempt: Attempt, token: UUID) {
        guard let entry = inFlight[attempt.id], entry.token == token else { return }
        inFlight[attempt.id] = nil
        entry.subscribers.values.forEach {
            $0.yield(attempt)
            $0.finish()
        }
    }

    private func removeSubscriber(_ subscriberID: UUID, from screenshotID: Screenshot.ID) {
        guard var entry = inFlight[screenshotID] else { return }
        entry.subscribers[subscriberID] = nil
        if entry.subscribers.isEmpty {
            inFlight[screenshotID] = nil
            entry.task.cancel()
        } else {
            inFlight[screenshotID] = entry
        }
    }
}
