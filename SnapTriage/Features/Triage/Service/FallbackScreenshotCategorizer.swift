//
//  FallbackScreenshotCategorizer.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//
//  Runtime support for the classification cascade: the real foundation-model
//  stage, the gate that serializes model inference, and the metrics sink.
//

import Foundation
import CoreGraphics
import os

// MARK: - Foundation model stage

/// The real, last-resort model stage. Prefers the multimodal (pixels + OCR) path
/// on iOS 27, falls back to text-only on iOS 26, and returns `nil` on any
/// unavailable or error state (iOS < 26, Apple Intelligence off, model still
/// downloading, inference failure) so the cascade can degrade to the heuristic.
///
/// Every call funnels through ``FoundationModelGate`` so only a small bounded
/// number of independent sessions can infer concurrently. Each screenshot runs
/// in a fresh session (see ``FoundationModelScreenshotCategorizer``), so
/// transcripts never bleed between screenshots.
struct FoundationModelClassifier: ScreenshotModelClassifier {

    func classify(ocr: OCRResult, image: CGImage?) async -> ModelVerdict? {
        await FoundationModelGate.shared.run {
            if let image, #available(iOS 27.0, *) {
                if let category = try? await FoundationModelScreenshotCategorizer().category(for: ocr, image: image) {
                    return ModelVerdict(category: category, usedImage: true)
                }
            }
            if #available(iOS 26.0, *) {
                guard let category = try? await FoundationModelScreenshotCategorizer().category(for: ocr) else {
                    return nil
                }
                return ModelVerdict(category: category, usedImage: false)
            }
            return nil
        }
    }

    func prewarm() {
        if #available(iOS 26.0, *) {
            FoundationModelScreenshotCategorizer().prewarm()
        }
    }
}

// MARK: - Bounded model gate

/// Allows two independent model sessions at a time, process-wide. Apple forbids
/// concurrent requests *within one LanguageModelSession*; this classifier uses a
/// fresh session per screenshot, so a small two-lane window is valid while still
/// preventing a four-item OCR burst from overwhelming the model/ANE.
actor FoundationModelGate {
    static let shared = FoundationModelGate(maxConcurrentRequests: 2)

    private let maxConcurrentRequests: Int
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrentRequests: Int = 2) {
        precondition(maxConcurrentRequests > 0)
        self.maxConcurrentRequests = maxConcurrentRequests
        self.availablePermits = maxConcurrentRequests
    }

    func run<T: Sendable>(_ body: @Sendable @escaping () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await body()
    }

    private func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            availablePermits += 1
            assert(availablePermits <= maxConcurrentRequests)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

// MARK: - Metrics

/// Where a screenshot's verdict came from, for aggregate routing counts.
enum ClassificationEngine: String, Sendable {
    case heuristic
    case vision
    case foundationModel
}

/// A timed stage of the per-screenshot pipeline.
enum ClassificationStage: String, Sendable {
    case imageLoad
    case ocr
    case heuristic
    case vision
    case foundationModel
    case total
}

/// Lightweight instrumentation sink. Timing feeds Instruments (via signposts);
/// counts feed the "how much of the library needed the model" question the MVP
/// targets. Implementations must never log OCR text, codes, IDs, or other
/// sensitive content — only stage names, engine names, and durations.
protocol ClassificationMetrics: Sendable {
    func record(_ stage: ClassificationStage, _ duration: Duration)
    func recordEngine(_ engine: ClassificationEngine, usedImage: Bool)
    func recordResolution(_ source: ClassificationSource)
    func recordNeedsReview()
    func recordFailure()
}

/// Default sink: emits `os_signpost` intervals per stage for Instruments and
/// keeps running aggregate counts behind a lock, exposed via ``snapshot()`` for
/// debug logging. Safe to share across the concurrent classify pipeline.
final class OSLogClassificationMetrics: ClassificationMetrics, @unchecked Sendable {

    struct Counts: Sendable, Equatable {
        var heuristicCalls = 0
        var visionCalls = 0
        var foundationModelCalls = 0
        var foundationModelImageCalls = 0
        var heuristicResolutions = 0
        var visionResolutions = 0
        var foundationModelResolutions = 0
        var cacheResolutions = 0
        var fallbackResolutions = 0
        var needsReview = 0
        var failures = 0
    }

    private let signposter = OSSignposter(subsystem: "com.snaptriage.classification", category: .pointsOfInterest)
    private let state = OSAllocatedUnfairLock(initialState: Counts())

    func record(_ stage: ClassificationStage, _ duration: Duration) {
        let id = signposter.makeSignpostID()
        let interval = signposter.beginInterval("stage", id: id, "\(stage.rawValue)")
        signposter.endInterval("stage", interval, "\(duration.milliseconds)ms")
    }

    func recordEngine(_ engine: ClassificationEngine, usedImage: Bool) {
        state.withLock { counts in
            switch engine {
            case .heuristic: counts.heuristicCalls += 1
            case .vision:    counts.visionCalls += 1
            case .foundationModel:
                counts.foundationModelCalls += 1
                if usedImage { counts.foundationModelImageCalls += 1 }
            }
        }
    }

    func recordResolution(_ source: ClassificationSource) {
        state.withLock { counts in
            switch source {
            case .heuristic:                                  counts.heuristicResolutions += 1
            case .vision:                                     counts.visionResolutions += 1
            case .foundationModelText, .foundationModelMultimodal: counts.foundationModelResolutions += 1
            case .cached:                                     counts.cacheResolutions += 1
            case .fallback:                                   counts.fallbackResolutions += 1
            }
        }
    }

    func recordNeedsReview() { state.withLock { $0.needsReview += 1 } }
    func recordFailure()     { state.withLock { $0.failures += 1 } }

    func snapshot() -> Counts { state.withLock { $0 } }
}

/// No-op sink for previews and tests that don't care about instrumentation.
struct NoopClassificationMetrics: ClassificationMetrics {
    func record(_ stage: ClassificationStage, _ duration: Duration) {}
    func recordEngine(_ engine: ClassificationEngine, usedImage: Bool) {}
    func recordResolution(_ source: ClassificationSource) {}
    func recordNeedsReview() {}
    func recordFailure() {}
}

private extension Duration {
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1_000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
