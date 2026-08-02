//
//  ScreenshotDisposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

/// What the app recommends doing with a screenshot. Retention is deliberately a
/// three-state decision, not a keep/delete binary: a screenshot the pipeline is
/// unsure about must never be presented as a safe deletion candidate.
///
/// - `useful`: worth keeping (records, credentials, travel/event docs).
/// - `safeToDelete`: ephemeral, a safe reclaim candidate.
/// - `needsReview`: unknown, low-confidence, or a category with no confident
///   auto-policy. Excluded from reclaimable bytes and never pre-selected for
///   deletion — the user decides.
enum ScreenshotDisposition: Equatable {
    case useful
    case safeToDelete
    case needsReview
}

// MARK: - Classification result

/// How sure the pipeline is. A coarse tier, not a probability: the on-device
/// heuristic scores against a rule table and the foundation model does not
/// report a calibrated likelihood, so anything finer would be false precision.
enum ClassificationConfidence: String, Codable, Sendable, Equatable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low:    0
        case .medium: 1
        case .high:   2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// Which stage produced the verdict. Drives instrumentation (how often each
/// engine resolves a screenshot) and explains a result during debugging.
enum ClassificationSource: String, Codable, Sendable, Equatable {
    case heuristic
    case vision
    case foundationModelText
    case foundationModelMultimodal
    /// The heuristic used as a safe fallback when the model could not run.
    case fallback
    /// Loaded from the persisted classification store; no work re-run.
    case cached
}

/// A single, non-sensitive reason a category won. Stores signal *labels*
/// (`"receiptAnchor"`, `"money"`, `"model"`) and their weights — never OCR text,
/// OTP codes, IDs, or prompt transcripts — so it is safe to persist and to log
/// while still letting tests and debugging explain a verdict.
struct ClassificationEvidence: Codable, Sendable, Equatable, Hashable {
    let signal: String
    var weight: Double?

    init(_ signal: String, weight: Double? = nil) {
        self.signal = signal
        self.weight = weight
    }
}

/// The core output of the classification pipeline. Replaces the bare
/// ``ScreenshotCategory`` so callers can reason about confidence and provenance,
/// and so retention (`useful` / `safeToDelete` / `needsReview`) can be derived
/// rather than hard-coded to the category.
struct ScreenshotClassification: Codable, Sendable, Equatable {
    let category: ScreenshotCategory
    let confidence: ClassificationConfidence
    let source: ClassificationSource
    var evidence: [ClassificationEvidence]

    init(
        category: ScreenshotCategory,
        confidence: ClassificationConfidence,
        source: ClassificationSource,
        evidence: [ClassificationEvidence] = []
    ) {
        self.category = category
        self.confidence = confidence
        self.source = source
        self.evidence = evidence
    }

    /// The retention recommendation for this classification. See ``RetentionPolicy``.
    var disposition: ScreenshotDisposition { RetentionPolicy.disposition(for: self) }

    /// A screen the whole cascade could not resolve. Always `needsReview`, never
    /// an automatic deletion candidate.
    static let unresolved = ScreenshotClassification(
        category: .other,
        confidence: .low,
        source: .fallback
    )

    /// Re-stamps a stored classification as a cache hit, preserving its verdict
    /// while recording that no work was re-run to produce it.
    func asCached() -> ScreenshotClassification {
        ScreenshotClassification(
            category: category,
            confidence: confidence,
            source: .cached,
            evidence: evidence
        )
    }
}

/// Maps a classification to a retention recommendation. This is the one place
/// category and retention meet, keeping the two concerns decoupled everywhere
/// else.
///
/// Rules (from the MVP spec):
/// - `.other`, and any low-confidence verdict, are `needsReview` — never
///   auto-deletable, regardless of the category's inherent leaning.
/// - Otherwise the category's ``ScreenshotCategory/baseDisposition`` applies,
///   which itself sends genuinely ambiguous buckets (`shopping`, `other`) to
///   `needsReview`.
enum RetentionPolicy {
    static func disposition(for classification: ScreenshotClassification) -> ScreenshotDisposition {
        if classification.category == .other { return .needsReview }
        if classification.confidence == .low { return .needsReview }
        return classification.category.baseDisposition
    }
}
