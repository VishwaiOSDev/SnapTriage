//
//  FallbackScreenshotCategorizer.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation

/// Prefers the foundation model, degrades to a heuristic when it can't run.
///
/// The model is unavailable on iOS < 26, when Apple Intelligence is off, while
/// the model is still downloading, or on any inference error. In every one of
/// those cases the user still gets a category — just from the rule table — so
/// classification never throws and never returns empty to the view model.
///
/// The heuristic also acts as a second opinion in two places:
/// - When the model answers `other` (its "don't know"), structural signals —
///   money amounts, OTP shapes, addresses — can still rescue a real category.
/// - When the model picks a safe-to-delete category but the rule table finds
///   keep-worthy evidence (policy numbers, ID markers, totals), keep wins.
///   Misclassification cost is asymmetric — deleting an insurance card is
///   unrecoverable, keeping junk is a minor annoyance — so a single model
///   verdict is never enough to send document-shaped text to the delete pile.
///   The override only ever upgrades toward keep, never the other way.
struct FallbackScreenshotCategorizer: ScreenshotCategorizer {

    typealias PrimaryCategorizer = @Sendable (OCRResult) async throws -> ScreenshotCategory

    /// `nil` means "use the foundation model"; tests inject a stub here.
    private let primary: PrimaryCategorizer?
    let fallback: ScreenshotCategorizer

    init(
        primary: PrimaryCategorizer? = nil,
        fallback: ScreenshotCategorizer = HeuristicScreenshotCategorizer()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func category(for result: OCRResult) async -> ScreenshotCategory {
        guard let category = await primaryCategory(for: result) else {
            return await fallback.category(for: result)
        }
        if category == .other {
            let secondOpinion = await fallback.category(for: result)
            return secondOpinion == .other ? .other : secondOpinion
        }
        if category.disposition == .safeToDelete {
            let secondOpinion = await fallback.category(for: result)
            if secondOpinion.disposition == .useful { return secondOpinion }
        }
        return category
    }

    /// `nil` when no primary can run at all — older OS or inference failure.
    private func primaryCategory(for result: OCRResult) async -> ScreenshotCategory? {
        if let primary {
            return try? await primary(result)
        }
        if #available(iOS 26.0, *) {
            return try? await FoundationModelScreenshotCategorizer().category(for: result)
        }
        return nil
    }

    func prewarm() {
        if #available(iOS 26.0, *) {
            FoundationModelScreenshotCategorizer().prewarm()
        }
    }
}
