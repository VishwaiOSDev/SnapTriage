//
//  EmptyReviewView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import SwiftUI

/// Shown when nothing is marked for deletion — the triage pass came back clean.
struct EmptyReviewView: View {
    var body: some View {
        ContentUnavailableView {
            Label(Strings.Review.emptyTitle, systemImage: "checkmark.circle")
        } description: {
            Text(Strings.Review.emptyMessage)
        }
    }
}
