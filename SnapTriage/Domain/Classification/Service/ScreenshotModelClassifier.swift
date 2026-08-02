//
//  ScreenshotModelClassifier.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import CoreGraphics

/// One verdict from the foundation model. `usedImage` records whether the
/// multimodal (pixels + OCR) path ran, so the caller can label the source
/// `foundationModelMultimodal` vs `foundationModelText` and tests can assert it.
struct ModelVerdict: Sendable, Equatable {
    let category: ScreenshotCategory
    let usedImage: Bool
}

/// The expensive, last-resort stage of the cascade. Kept behind a protocol so
/// the orchestrator can be driven by a recording test double that counts calls
/// and never touches Apple Intelligence.
///
/// Returns `nil` when the model cannot run at all (iOS < 26, Apple Intelligence
/// off, still downloading, or any inference error) — the caller then falls back
/// to the deterministic heuristic. Implementations must serialize inference (a
/// single on-device model session) and run each screenshot in a fresh context.
protocol ScreenshotModelClassifier: Sendable {
    func classify(ocr: OCRResult, image: CGImage?) async -> ModelVerdict?
    func prewarm()
}

extension ScreenshotModelClassifier {
    func prewarm() {}
}
