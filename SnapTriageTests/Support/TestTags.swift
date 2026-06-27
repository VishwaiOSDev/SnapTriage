//
//  TestTags.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 20/06/26.
//

import Testing

/// Shared tags so suites and individual tests can be filtered as cross-cutting
/// groups in the Xcode test navigator and in test plans (e.g. run only `.fast`).
extension Tag {
    /// Anything in the screenshot-classification domain.
    @Tag static var categorization: Self
    /// `CategorizeScreenshotUseCase` text-vs-image routing decisions.
    @Tag static var routing: Self
    /// The on-device `HeuristicScreenshotCategorizer` rule table.
    @Tag static var heuristics: Self
    /// Degrade / safety-net paths (empty text, inconclusive image, no image).
    @Tag static var fallback: Self
    /// Pure, in-memory, no I/O — safe to run on every keystroke.
    @Tag static var fast: Self
    /// The Review feature: load/select/delete flows.
    @Tag static var review: Self
}
