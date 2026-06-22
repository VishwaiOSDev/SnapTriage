//
//  TriageStat.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

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

struct OverviewSummary: Equatable {
    var usefulCount = 0
    var usefulBytes = 0
    var safeCount = 0
    var safeBytes = 0
    var totalCount = 0
    var unknownCount = 0

    var reclaimableBytes: Int { safeBytes }

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
        }
    }
}

extension OverviewSummary {
    static let empty = OverviewSummary()
}
