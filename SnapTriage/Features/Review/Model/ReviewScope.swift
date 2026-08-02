//
//  ReviewScope.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 02/08/26.
//

import Foundation

/// Which screenshots the Review screen is answering for.
///
/// The two scopes exist because Review serves two different questions. The
/// triage inbox asks "what did I decide, and what does the app think is safe?"
/// — it is deliberately narrow, and a `useful` screenshot never appears in it.
/// A category scope asks "show me this bucket", which is the only way a user can
/// look at, say, their OTP screenshots before ruling on them. Bulk verdicts are
/// only ever offered here, where the photos are on screen.
enum ReviewScope: Hashable, Sendable {
    case triage
    case category(ScreenshotCategory)

    var category: ScreenshotCategory? {
        switch self {
        case .triage: nil
        case .category(let category): category
        }
    }

    var isCategory: Bool { category != nil }

    var title: String {
        category?.title ?? Strings.Review.title
    }
}
