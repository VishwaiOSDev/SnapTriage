//
//  CategorizeScreenshotUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import CoreGraphics
import Foundation

/// Orchestrates the cheap-first classification cascade for one screenshot:
///
/// 1. **Heuristic** — deterministic rule scoring over OCR features. Cheap; runs
///    for every screenshot.
/// 2. **Deterministic bypass** — a high-confidence, high-margin heuristic verdict
///    with the category's required evidence and no conflicting protected signal
///    returns immediately, spending *no* model work.
/// 3. **Vision** — for sparse/image-led screens the transcript can't describe.
/// 4. **Foundation model** — only the remaining ambiguous screens, bounded to
///    two independent sessions through ``FoundationModelGate``.
/// 5. **Fallback / needs-review** — when the model can't run, the deterministic
///    verdict stands if it has real evidence; otherwise the screen is
///    `unresolved` (needs review), never an automatic deletion candidate.
///
/// The reverse of the old model-first pipeline: most screenshots now resolve at
/// step 2 without ever loading pixels or invoking Apple Intelligence.
struct CategorizeScreenshotUseCase: Sendable {

    let heuristic: HeuristicScreenshotCategorizer
    let vision: ImageContentClassifier
    let model: ScreenshotModelClassifier
    let imageLoader: PhotoLibraryService
    let metrics: ClassificationMetrics

    /// Fewer recognized words than this means the screen is image-led (a photo, a
    /// signature, a scanned card) — the transcript can't be trusted, so ask the pixels.
    private let minimumWords = 4
    private let longEdge: CGFloat = 1024
    /// A safe-to-delete heuristic winner may only bypass the model when it clears
    /// a keep-worthy runner-up by at least this margin — otherwise the asymmetric
    /// cost of a wrong delete warrants a model second opinion.
    private let protectedMargin = 2.0

    init(
        heuristic: HeuristicScreenshotCategorizer = HeuristicScreenshotCategorizer(),
        vision: ImageContentClassifier = VisionImageContentClassifier(),
        model: ScreenshotModelClassifier = FoundationModelClassifier(),
        imageLoader: PhotoLibraryService,
        metrics: ClassificationMetrics = NoopClassificationMetrics()
    ) {
        self.heuristic = heuristic
        self.vision = vision
        self.model = model
        self.imageLoader = imageLoader
        self.metrics = metrics
    }

    /// Warms the language model while OCR is still running, hiding model load behind it.
    func prewarm() {
        model.prewarm()
    }

    func execute(
        _ ocr: OCRResult,
        sourceImage: CGImage? = nil
    ) async -> ScreenshotClassification {
        let clock = ContinuousClock()
        let start = clock.now
        let classification = await classify(ocr, sourceImage: sourceImage, clock: clock)
        metrics.record(.total, clock.now - start)
        metrics.recordResolution(classification.source)
        if classification.disposition == .needsReview { metrics.recordNeedsReview() }
        return classification
    }

    private func classify(
        _ ocr: OCRResult,
        sourceImage: CGImage?,
        clock: ContinuousClock
    ) async -> ScreenshotClassification {
        // 1. Heuristic — cheap and deterministic.
        let heuristicStart = clock.now
        let result = heuristic.evaluate(ocr)
        metrics.record(.heuristic, clock.now - heuristicStart)
        metrics.recordEngine(.heuristic, usedImage: false)

        // 2. High-confidence deterministic bypass: no pixels, no model.
        if result.tier == .high, canBypass(result) {
            return classification(from: result, source: .heuristic, confidence: .high)
        }
        // A confident structured plan is a resolved non-category; don't spend the model.
        if result.abstentionReason == "structuredPlan" {
            return ScreenshotClassification(
                category: .other, confidence: .medium, source: .heuristic, evidence: result.evidence
            )
        }

        // 3. Load pixels once if a later stage will use them.
        let sparse = isTextSparse(ocr)
        var wantsImage = sparse
        if #available(iOS 27.0, *) { wantsImage = true } // the multimodal model reads the interface
        var image = sourceImage
        if wantsImage, image == nil {
            let imageStart = clock.now
            image = await imageLoader.cgImage(for: ocr.screenshotID, longEdge: longEdge)
            metrics.record(.imageLoad, clock.now - imageStart)
        }

        // 4. Vision for image-led (sparse text) screens.
        if sparse, let image {
            let visionStart = clock.now
            let visual = await vision.category(for: image)
            metrics.record(.vision, clock.now - visionStart)
            metrics.recordEngine(.vision, usedImage: true)
            if let visual, visual != .other {
                // A generic Vision label such as "card" or "document" is less
                // specific than corroborated official-ID text. Preserve the ID
                // instead of allowing Vision to erase that distinction.
                if HeuristicScreenshotCategorizer.isIdentityDocument(ocr) {
                    return classification(from: result, source: .heuristic, confidence: .high)
                }
                return ScreenshotClassification(
                    category: visual, confidence: .medium, source: .vision,
                    evidence: [ClassificationEvidence("vision")]
                )
            }
        }

        // 5. Foundation model — only the ambiguous remainder, bounded by the gate.
        let modelStart = clock.now
        let verdict = await model.classify(ocr: ocr, image: image)
        metrics.record(.foundationModel, clock.now - modelStart)
        if let verdict {
            metrics.recordEngine(.foundationModel, usedImage: verdict.usedImage)
            let category = applySafety(verdict, heuristic: result, ocr: ocr)
            let source: ClassificationSource = verdict.usedImage ? .foundationModelMultimodal : .foundationModelText
            // The model's self-reported certainty is not calibrated, so a real
            // category is `.medium`, never `.high`; `.other` stays low → needs review.
            let confidence: ClassificationConfidence = category == .other ? .low : .medium
            return ScreenshotClassification(
                category: category, confidence: confidence, source: source,
                evidence: [ClassificationEvidence("model")]
            )
        }

        // 6. Model unavailable → the deterministic verdict stands if it has real
        // evidence; otherwise needs review. Uncertain content is never auto-deleted.
        if result.category != .other, result.tier >= .medium {
            return classification(from: result, source: .fallback, confidence: result.tier)
        }
        return .unresolved
    }

    // MARK: - Cascade policy

    /// Whether a high-confidence heuristic verdict is trustworthy enough to skip
    /// the model. Keep-worthy winners always qualify; a safe-to-delete or
    /// needs-review winner must clear any keep-worthy runner-up by a safe margin,
    /// because the cost of a wrong delete is asymmetric.
    private func canBypass(_ result: HeuristicResult) -> Bool {
        guard result.category != .other else { return false }
        if result.category.baseDisposition == .useful { return true }
        if let runnerUp = result.runnerUp,
           runnerUp.baseDisposition == .useful,
           result.margin < protectedMargin {
            return false
        }
        return true
    }

    /// Folds asymmetric-cost safety over a raw model verdict:
    /// - A structured plan overrides a safe-to-delete guess (`other`).
    /// - A model `other` is rescued toward a keep-worthy heuristic verdict.
    /// - A safe-to-delete model verdict yields to keep-worthy heuristic evidence,
    ///   except a *visual* game verdict, which keeps its edge over receipt-shaped
    ///   OCR unless the heuristic found a formal record or ID.
    private func applySafety(
        _ verdict: ModelVerdict,
        heuristic result: HeuristicResult,
        ocr: OCRResult
    ) -> ScreenshotCategory {
        let category = verdict.category
        // Identity is a protected class: once issuer/number/field structure is
        // corroborated, neither chat-like short lines nor a generic document
        // model verdict may demote it.
        if HeuristicScreenshotCategorizer.isIdentityDocument(ocr) {
            return .identity
        }
        if category.baseDisposition == .safeToDelete,
           HeuristicScreenshotCategorizer.isStructuredPlan(ocr) {
            return .other
        }
        if category == .other {
            if result.category.baseDisposition == .useful, result.tier >= .medium {
                return result.category
            }
            return .other
        }
        if category.baseDisposition == .safeToDelete,
           result.category.baseDisposition == .useful,
           result.tier >= .medium {
            if verdict.usedImage, category == .game,
               result.category != .document, result.category != .identity {
                return category
            }
            return result.category
        }
        return category
    }

    private func classification(
        from result: HeuristicResult,
        source: ClassificationSource,
        confidence: ClassificationConfidence
    ) -> ScreenshotClassification {
        ScreenshotClassification(
            category: result.category,
            confidence: confidence,
            source: source,
            evidence: result.evidence
        )
    }

    private func isTextSparse(_ result: OCRResult) -> Bool {
        let words = result.transcript.split { $0.isWhitespace || $0.isNewline }
        return words.count < minimumWords
    }
}
