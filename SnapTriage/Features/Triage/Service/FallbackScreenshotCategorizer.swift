//
//  FallbackScreenshotCategorizer.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation
import CoreGraphics

/// Prefers the foundation model, degrades to a heuristic when it can't run.
///
/// The model is unavailable on iOS < 26, when Apple Intelligence is off, while
/// the model is still downloading, or on any inference error. In every one of
/// those cases the user still gets a category — just from the rule table — so
/// classification never throws and never returns empty to the view model.
///
/// The heuristic also acts as a second opinion in two places:
/// - When the model answers `other` (its "don't know"), heuristic evidence for any
///   keep-worthy category — anything the app treats as `.useful` — can rescue a real
///   category. Deleting a boarding pass or invite the model punted on is unrecoverable.
///   Safe-to-delete guesses like `game` must not overrule an abstention, because their
///   evidence is ambiguous without the screenshot pixels.
/// - When the model picks a safe-to-delete category but the rule table finds
///   keep-worthy evidence (policy numbers, ID markers, totals), keep wins.
///   Misclassification cost is asymmetric — deleting an insurance card is
///   unrecoverable, keeping junk is a minor annoyance — so a single model
///   verdict is never enough to send document-shaped text to the delete pile.
///   A multimodal game verdict is the exception: visual gameplay evidence wins
///   over receipt-shaped OCR unless the fallback finds a formal record or ID.
struct FallbackScreenshotCategorizer: ScreenshotCategorizer {

    typealias PrimaryCategorizer = @Sendable (OCRResult) async throws -> ScreenshotCategory
    typealias MultimodalPrimaryCategorizer = @Sendable (OCRResult, CGImage) async throws -> ScreenshotCategory

    private enum PrimarySource: Equatable {
        case text
        case multimodal
    }

    private struct PrimaryVerdict {
        let category: ScreenshotCategory
        let source: PrimarySource
    }

    /// `nil` means "use the foundation model"; tests inject a stub here.
    private let primary: PrimaryCategorizer?
    /// `nil` means "use the Foundation Models image attachment path on iOS 27+."
    private let multimodalPrimary: MultimodalPrimaryCategorizer?
    let fallback: ScreenshotCategorizer

    init(
        primary: PrimaryCategorizer? = nil,
        multimodalPrimary: MultimodalPrimaryCategorizer? = nil,
        fallback: ScreenshotCategorizer = HeuristicScreenshotCategorizer()
    ) {
        self.primary = primary
        self.multimodalPrimary = multimodalPrimary
        self.fallback = fallback
    }

    func category(for result: OCRResult, image: CGImage?) async -> ScreenshotCategory {
        guard let verdict = await primaryCategory(for: result, image: image) else {
            return await fallback.category(for: result, image: image)
        }
        let category = verdict.category

        // A routine/checklist has no dedicated category. Its repeated day/task/quantity shape
        // is stronger than incidental words such as "level" or "battle" in one exercise name.
        if category.disposition == .safeToDelete,
           HeuristicScreenshotCategorizer.isStructuredPlan(result) {
            return .other
        }
        if category == .other {
            let secondOpinion = await fallback.category(for: result, image: image)
            return shouldRescueOther(with: secondOpinion) ? secondOpinion : .other
        }
        if category.disposition == .safeToDelete {
            let secondOpinion = await fallback.category(for: result, image: image)
            if secondOpinion.disposition == .useful,
               shouldPreferFallback(secondOpinion, over: verdict) {
                return secondOpinion
            }
        }
        return category
    }

    /// `nil` when no primary can run at all — older OS or inference failure.
    private func primaryCategory(for result: OCRResult, image: CGImage?) async -> PrimaryVerdict? {
        if let image, let multimodalPrimary, let category = try? await multimodalPrimary(result, image) {
            return PrimaryVerdict(category: category, source: .multimodal)
        }
        if let primary {
            guard let category = try? await primary(result) else { return nil }
            return PrimaryVerdict(category: category, source: .text)
        }
        if let image, #available(iOS 27.0, *) {
            if let category = try? await FoundationModelScreenshotCategorizer().category(for: result, image: image) {
                return PrimaryVerdict(category: category, source: .multimodal)
            }
        }
        if #available(iOS 26.0, *) {
            guard let category = try? await FoundationModelScreenshotCategorizer().category(for: result) else {
                return nil
            }
            return PrimaryVerdict(category: category, source: .text)
        }
        return nil
    }

    private func shouldPreferFallback(
        _ fallbackCategory: ScreenshotCategory,
        over primary: PrimaryVerdict
    ) -> Bool {
        // A multimodal game verdict has visual evidence that the OCR-only heuristic cannot see.
        // Still allow an ID or formal record to win, because sending it to the delete queue has
        // the highest cost. Other useful labels remain ordinary OCR tie-breaks.
        guard primary.source == .multimodal, primary.category == .game else { return true }
        return fallbackCategory == .document || fallbackCategory == .identity
    }

    private func shouldRescueOther(with category: ScreenshotCategory) -> Bool {
        // Only upgrade toward keep. Every `.useful` category is one the app already treats as
        // keep-worthy, so heuristic evidence for it can overrule the model's abstention. Safe-to-
        // delete guesses (game, social, article, …) are excluded by the same rule: without the
        // pixels their evidence is too ambiguous to overturn an explicit "don't know".
        category.disposition == .useful
    }

    func prewarm() {
        if #available(iOS 26.0, *) {
            FoundationModelScreenshotCategorizer().prewarm()
        }
    }
}
