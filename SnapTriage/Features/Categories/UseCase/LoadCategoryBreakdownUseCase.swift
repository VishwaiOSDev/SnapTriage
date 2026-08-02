//
//  LoadCategoryBreakdownUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import Foundation

/// Groups the screenshots still awaiting a verdict by the category the
/// classifier already assigned them.
///
/// Reads the classification cache and never drives the pipeline: the whole point
/// of this screen is to spend work that has *already* been done. A cold library
/// therefore shows an honest "still analyzing" count instead of blocking.
struct LoadCategoryBreakdownUseCase {

    let loadScreenshots: LoadScreenshotsUseCase
    let classifyLibrary: ClassifyLibraryUseCase
    let decisions: TriageDecisionStore

    func execute() async throws -> CategoryBreakdown {
        let screenshots = try await loadScreenshots.execute()
        guard !screenshots.isEmpty else { return .empty }

        let classifications = await classifyLibrary.cachedClassifications()
        let verdicts = decisions.allDecisions()

        var ids: [ScreenshotCategory: [Screenshot.ID]] = [:]
        var bytes: [ScreenshotCategory: Int] = [:]
        var unclassified = 0
        var decided = 0

        for screenshot in screenshots {
            guard verdicts[screenshot.id] == nil else {
                decided += 1
                continue
            }
            guard let classification = classifications[screenshot.id] else {
                unclassified += 1
                continue
            }
            let category = classification.category
            ids[category, default: []].append(screenshot.id)
            bytes[category, default: 0] += screenshot.byteSize
        }

        var groups: [CategoryGroup] = ids.map { category, members in
            CategoryGroup(
                // The group's leaning is the category's own, not any one
                // member's: per-screenshot confidence varies inside a bucket,
                // and a row summarising 300 screenshots must not inherit the
                // last one's verdict.
                category: category,
                disposition: category.baseDisposition,
                ids: members,
                byteSize: bytes[category] ?? 0
            )
        }

        // Biggest bucket first: that is where a single tap saves the most work.
        // Ties break on category name so the order is stable across reloads.
        groups.sort { lhs, rhs in
            lhs.count == rhs.count
                ? lhs.category.rawValue < rhs.category.rawValue
                : lhs.count > rhs.count
        }

        return CategoryBreakdown(
            groups: groups,
            unclassifiedCount: unclassified,
            decidedCount: decided
        )
    }
}
