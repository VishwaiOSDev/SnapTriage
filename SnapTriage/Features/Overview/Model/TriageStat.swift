//
//  TriageStat.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

/// A single stat tile in the Overview summary card. Pure display shape — the view
/// builds these from `OverviewSummary` with the right formatters.
struct TriageStat: Identifiable, Equatable {
    
    enum Indicator: Equatable {
        case icon(String)
        case progress(Double)
    }
    
    enum Kind: Hashable { case useful, safeToDelete, reclaimable }
    
    let id: Kind
    let value: String
    let title: String
    let detail: String?
    let indicator: Indicator
}
struct FeatureHighlight: Identifiable, Equatable {
    let id = UUID()
    let systemImage: String
    let title: String
    let subtitle: String
}

extension FeatureHighlight {
    
    static let defaults: [FeatureHighlight] = [
        FeatureHighlight(
            systemImage: "shield.lefthalf.filled",
            title: Strings.Overview.onDeviceTitle,
            subtitle: Strings.Overview.onDeviceSubtitle
        ),
        FeatureHighlight(
            systemImage: "sparkles",
            title: Strings.Overview.intelligentTitle,
            subtitle: Strings.Overview.intelligentSubtitle
        )
    ]
}

/// Aggregate counts and sizes behind the Overview screen. Raw numbers only;
/// formatting lives in the view.
struct OverviewSummary: Equatable {
    var usefulCount = 0
    var usefulBytes = 0
    var safeCount = 0
    var safeBytes = 0
    /// Screenshots the pipeline classified but is not confident enough to auto-act
    /// on (unknown, low-confidence, or ambiguous categories). Deliberately kept out
    /// of the reclaimable figure — they are never a safe deletion candidate.
    var reviewCount = 0
    var reviewBytes = 0
    var totalCount = 0
    /// Screenshots that finished the pipeline but could not be classified
    /// (e.g. iCloud-only assets whose image failed to load).
    var unknownCount = 0

    /// Headline "reclaimable" figure is the size of the safe-to-delete set only.
    /// Needs-review bytes never count toward reclaimable space.
    var reclaimableBytes: Int { safeBytes }

    /// Share of the library that is safe to delete (matches the reference's 85%).
    var reclaimableRatio: Double {
        totalCount == 0 ? 0 : Double(safeCount) / Double(totalCount)
    }

    mutating func add(bytes: Int, disposition: ScreenshotDisposition) {
        switch disposition {
        case .useful:
            usefulCount += 1
            usefulBytes += bytes
        case .safeToDelete:
            safeCount += 1
            safeBytes += bytes
        case .needsReview:
            reviewCount += 1
            reviewBytes += bytes
        }
    }
}

extension OverviewSummary {
    static let empty = OverviewSummary()
    
    // Filled sample for previews; mirrors the reference design.
    static let sample = OverviewSummary(
        usefulCount: 182,
        usefulBytes: 512_000_000,
        safeCount: 1_059,
        safeBytes: 3_200_000_000,
        totalCount: 1_241
    )
}
