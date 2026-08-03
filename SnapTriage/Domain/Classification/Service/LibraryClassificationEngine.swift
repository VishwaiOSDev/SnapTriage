//
//  LibraryClassificationEngine.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

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

    func clearCache() async {
        let running = inFlight.values.map(\.task)
        inFlight.removeAll()
        running.forEach { $0.cancel() }
        await store.removeAll()
    }

    private static func perform(
        _ screenshot: Screenshot,
        recognizeText: RecognizeScreenshotTextUseCase,
        categorize: CategorizeScreenshotUseCase,
        store: CategoryStore
    ) async -> Attempt {
        guard !Task.isCancelled else {
            return Attempt(id: screenshot.id, classification: nil, resolution: .cancelled)
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
        } catch is CancellationError {
            return Attempt(id: screenshot.id, classification: nil, resolution: .cancelled)
        } catch {
            categorize.recordFailure()
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
