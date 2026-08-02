//
//  HeuristicScreenshotCategorizer.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import CoreGraphics
import Foundation

/// The rich outcome of one heuristic evaluation. Beyond the winning category it
/// exposes the runner-up, the raw score and margin, a confidence tier, the
/// matched evidence, and — when it abstains — why. The cascade uses all of this
/// to decide whether a deterministic verdict is trustworthy enough to skip the
/// foundation model.
struct HeuristicResult: Sendable, Equatable {
    let category: ScreenshotCategory
    let runnerUp: ScreenshotCategory?
    let score: Double
    /// Winner score minus runner-up score. A thin margin means an ambiguous
    /// screen even if the raw score is high.
    let margin: Double
    let tier: ClassificationConfidence
    let evidence: [ClassificationEvidence]
    /// Set when the winner did not clear the bar (below score, missing required
    /// evidence, structured plan, …). `nil` when a category was accepted.
    let abstentionReason: String?

    static let unresolved = HeuristicResult(
        category: .other, runnerUp: nil, score: 0, margin: 0,
        tier: .low, evidence: [], abstentionReason: "noEvidence"
    )
}

// MARK: - Heuristic classifier

/// On-device, no-network deterministic classifier. Lemmatizes the transcript (so
/// `followers` matches `follower`), mines structural signals via `NSDataDetector`
/// and regex (money, dates, codes, handles…), then scores every category against
/// a single declarative rule table.
///
/// Rules are data, not code: adding a category is one row in `rules`, plus an
/// optional required-evidence clause. This is the cheap, first stage of the
/// cascade — a high-confidence result here skips Vision and the foundation model
/// entirely — and doubles as the offline fallback when the model is unavailable
/// (iOS < 26, Apple Intelligence off, or model not yet downloaded).
struct HeuristicScreenshotCategorizer: Sendable {

    /// Below this a category is not eligible at all.
    private let minimumScore: Double
    /// A winner needs at least this score to *possibly* reach `.high`.
    private let highScore: Double
    /// …and at least this margin over the runner-up. A high raw score with a
    /// thin margin stays `.medium` so the cascade escalates it.
    private let highMargin: Double

    init(minimumScore: Double = 2.0, highScore: Double = 4.0, highMargin: Double = 1.5) {
        self.minimumScore = minimumScore
        self.highScore = highScore
        self.highMargin = highMargin
    }

    /// Back-compat convenience: the winning category (or `.other`). Prefer
    /// ``evaluate(_:)`` when confidence, evidence, or the runner-up matter.
    func category(for result: OCRResult, image: CGImage? = nil) async -> ScreenshotCategory {
        evaluate(result).category
    }

    /// The full deterministic evaluation. Pure and synchronous — feature
    /// extraction and scoring never touch I/O.
    func evaluate(_ result: OCRResult) -> HeuristicResult {
        guard !result.transcript.isEmpty else { return .unresolved }

        let features = TextFeatures(text: result.transcript)

        // Structural short-circuits. A membership card or record is protected
        // (promote to keep); a day/task routine has no category (resolve to other).
        // Identity runs before the generic document check because passports,
        // visas, and ID cards are themselves document-shaped and frequently
        // contain phone-number-like digit groups that otherwise resemble chat.
        if Self.isIdentityLike(features) {
            return HeuristicResult(
                category: .identity, runnerUp: nil, score: highScore, margin: highMargin,
                tier: .high, evidence: [ClassificationEvidence("identityStructure")],
                abstentionReason: nil
            )
        }
        if Self.isDocumentLike(features) {
            return HeuristicResult(
                category: .document, runnerUp: nil, score: highScore, margin: highMargin,
                tier: .high, evidence: [ClassificationEvidence("documentStructure")], abstentionReason: nil
            )
        }
        if Self.isStructuredPlan(features) {
            return HeuristicResult(
                category: .other, runnerUp: nil, score: minimumScore, margin: 0,
                tier: .medium, evidence: [ClassificationEvidence("structuredPlan")],
                abstentionReason: "structuredPlan"
            )
        }

        let scored = Self.rules
            .map { rule -> (category: ScreenshotCategory, score: Double, evidence: [ClassificationEvidence]) in
                let (score, evidence) = self.score(rule, features)
                return (rule.category, score, evidence)
            }
            .sorted { $0.score > $1.score }

        guard let best = scored.first else { return .unresolved }
        let runnerUp = scored.dropFirst().first { $0.score > 0 }
        let margin = best.score - (runnerUp?.score ?? 0)

        guard best.score >= minimumScore,
              Self.hasRequiredEvidence(for: best.category, features: features) else {
            return HeuristicResult(
                category: .other, runnerUp: best.category, score: best.score, margin: margin,
                tier: .low, evidence: best.evidence,
                abstentionReason: best.score < minimumScore ? "belowScore" : "missingRequiredEvidence"
            )
        }

        let tier: ClassificationConfidence = (best.score >= highScore && margin >= highMargin) ? .high : .medium
        return HeuristicResult(
            category: best.category, runnerUp: runnerUp?.category, score: best.score, margin: margin,
            tier: tier, evidence: best.evidence, abstentionReason: nil
        )
    }

    /// A reusable escape hatch for routines, study schedules, meal plans, chore lists, and
    /// similar task plans. They have no dedicated user-facing category, so `other` is correct.
    static func isStructuredPlan(_ result: OCRResult) -> Bool {
        guard !result.transcript.isEmpty else { return false }
        return isStructuredPlan(TextFeatures(text: result.transcript))
    }

    /// Whether OCR contains corroborated evidence of a government-issued
    /// identity document. Kept separately from scoring so generic chat/phone
    /// signals can never outvote a passport, visa, Aadhaar, PAN, or licence.
    static func isIdentityDocument(_ result: OCRResult) -> Bool {
        guard !result.transcript.isEmpty else { return false }
        return isIdentityLike(TextFeatures(text: result.transcript))
    }

    private func score(_ rule: CategoryRule, _ f: TextFeatures) -> (Double, [ClassificationEvidence]) {
        var total = 0.0
        var evidence: [ClassificationEvidence] = []

        let matchedTerms = rule.terms.intersection(f.terms)
        if !matchedTerms.isEmpty {
            let weight = rule.termWeight * Double(matchedTerms.count)
            total += weight
            evidence.append(ClassificationEvidence("terms", weight: weight))
        }
        for (signal, weight) in rule.signals {
            let value = f.value(for: signal)
            guard value > 0 else { continue }
            let contribution = weight * value
            total += contribution
            evidence.append(ClassificationEvidence(String(describing: signal), weight: contribution))
        }
        for (phrase, weight) in rule.phrases where f.lowercased.contains(phrase) {
            total += weight
            evidence.append(ClassificationEvidence("phrase:\(phrase)", weight: weight))
        }
        return (total, evidence)
    }
}
