//
//  ClassifyLibraryUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

/// Categorizes the whole screenshot library in the background and reports each
/// result as it lands. Throttled to a small concurrency window so OCR + the
/// classifier don't swamp the device, cached per screenshot so re-runs are cheap,
/// and fully cancelable via the stream's termination.
struct ClassifyLibraryUseCase {

    let recognizeText: RecognizeScreenshotTextUseCase
    let categorize: CategorizeScreenshotUseCase
    let store: CategoryStore

    private let concurrency = 4

    struct Progress: Sendable {
        let id: Screenshot.ID?
        let category: ScreenshotCategory?
        let completed: Int
        let total: Int
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

                await withTaskGroup(of: (Screenshot.ID, ScreenshotCategory?)?.self) { group in
                    func addNext() {
                        guard index < screenshots.count else { return }
                        let shot = screenshots[index]
                        index += 1
                        group.addTask(priority: .utility) { await classify(shot) }
                    }

                    for _ in 0..<min(concurrency, screenshots.count) { addNext() }

                    for await outcome in group {
                        if Task.isCancelled { break }
                        completed += 1
                        continuation.yield(
                            Progress(id: outcome?.0, category: outcome?.1, completed: completed, total: total)
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
    private func classify(_ shot: Screenshot) async -> (Screenshot.ID, ScreenshotCategory?)? {
        if Task.isCancelled { return nil }
        if let cached = await store.category(for: shot.id) {
            return (shot.id, cached)
        }
        do {
            let ocr = try await recognizeText.execute(screenshotID: shot.id)
            if Task.isCancelled { return nil }
            let category = await categorize.execute(ocr)
            await store.save(category, for: shot.id)
            return (shot.id, category)
        } catch is CancellationError {
            return nil
        } catch {
            return (shot.id, nil)
        }
    }
}
