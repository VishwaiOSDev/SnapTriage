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
struct FallbackScreenshotCategorizer: ScreenshotCategorizer {

    let fallback: ScreenshotCategorizer

    init(fallback: ScreenshotCategorizer = HeuristicScreenshotCategorizer()) {
        self.fallback = fallback
    }

    func category(for result: OCRResult) async -> ScreenshotCategory {
        if #available(iOS 26.0, *) {
            do {
                return try await FoundationModelScreenshotCategorizer().category(for: result)
            } catch {
                return await fallback.category(for: result)
            }
        }
        return await fallback.category(for: result)
    }

    func prewarm() {
        if #available(iOS 26.0, *) {
            FoundationModelScreenshotCategorizer().prewarm()
        }
    }
}
