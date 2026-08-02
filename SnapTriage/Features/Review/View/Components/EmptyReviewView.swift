//
//  EmptyReviewView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import SwiftUI

/// Shown when the scope has nothing left in it: a triage pass that came back
/// clean, or a category the user has now ruled on end to end.
struct EmptyReviewView: View {
    let scope: ReviewScope

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "checkmark.circle")
        } description: {
            Text(message)
        }
    }

    private var title: String {
        scope.isCategory ? Strings.Review.scopedEmptyTitle : Strings.Review.emptyTitle
    }

    private var message: String {
        guard let category = scope.category else { return Strings.Review.emptyMessage }
        return Strings.Review.scopedEmptyMessage(category.title)
    }
}
