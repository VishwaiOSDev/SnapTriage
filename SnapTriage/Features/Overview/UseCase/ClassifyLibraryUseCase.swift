//
//  ClassifyLibraryUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

/// Classifies the whole screenshot library in the background and reports each
/// result as it lands. Cached per screenshot so re-runs are cheap, and fully
/// cancelable via the stream's termination.
///
/// Concurrency is *stage-aware*, not one blind number applied to the whole
/// expensive pipeline. Cache hits return immediately. The cheap stages (OCR,
/// heuristic, Vision) run at a small bounded window; the foundation model has
/// its own smaller two-request limiter inside ``FoundationModelGate``. Most
/// screenshots resolve on the heuristic and never reach the model at all.
struct ClassifyLibraryUseCase {

    let recognizeText: RecognizeScreenshotTextUseCase
    let categorize: CategorizeScreenshotUseCase
    let store: CategoryStore

    /// Bounds the cheap OCR/heuristic/Vision stages. The model gate handles the
    /// expensive stage separately, so this is a throughput knob, not the model-
    /// concurrency knob.
    private let cheapConcurrency = 4

    struct Progress: Sendable {
        let id: Screenshot.ID?
        let classification: ScreenshotClassification?
        let completed: Int
        let total: Int
    }

    /// Starts the categorizer's model load early so the first classification
    /// doesn't pay the cold-start stall. Safe to call repeatedly.
    func prewarm() {
        categorize.prewarm()
    }

    /// Everything the store already knows, in one read. Callers fold these into
    /// their state before streaming `execute` over the remainder — streaming
    /// cache hits one by one after a relaunch animates totals up from zero.
    func cachedClassifications() async -> [Screenshot.ID: ScreenshotClassification] {
        await store.allClassifications()
    }

    // Utility priority throughout: OCR + inference saturate CPU/ANE, and at the
    // inherited user-initiated priority they starve UI rendering during bursts.
    func execute(_ screenshots: [Screenshot]) -> AsyncStream<Progress> {
        AsyncStream { continuation in
            let task = Task(priority: .utility) {
                categorize.prewarm()
                let total = screenshots.count
                var completed = 0
                var index = 0

                await withTaskGroup(of: (Screenshot.ID, ScreenshotClassification?)?.self) { group in
                    func addNext() {
                        guard index < screenshots.count else { return }
                        let shot = screenshots[index]
                        index += 1
                        group.addTask(priority: .utility) { await classify(shot) }
                    }

                    for _ in 0..<min(cheapConcurrency, screenshots.count) { addNext() }

                    for await outcome in group {
                        if Task.isCancelled { break }
                        completed += 1
                        continuation.yield(
                            Progress(id: outcome?.0, classification: outcome?.1, completed: completed, total: total)
                        )
                        addNext()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // Returns nil only when cancelled. A failed classification yields (id, nil)
    // so callers can count it as unknown rather than silently dropping it.
    private func classify(_ shot: Screenshot) async -> (Screenshot.ID, ScreenshotClassification?)? {
        if Task.isCancelled { return nil }
        if let cached = await store.classification(for: shot.id) {
            return (shot.id, cached.asCached())
        }
        do {
            let recognized = try await recognizeText.executeWithSourceImage(screenshotID: shot.id)
            if Task.isCancelled { return nil }
            let classification = await categorize.execute(
                recognized.result,
                sourceImage: recognized.sourceImage
            )
            await store.save(classification, for: shot.id)
            return (shot.id, classification)
        } catch is CancellationError {
            return nil
        } catch {
            return (shot.id, nil)
        }
    }
}
