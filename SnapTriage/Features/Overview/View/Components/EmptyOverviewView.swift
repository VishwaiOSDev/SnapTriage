//
//  EmptyOverviewView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import SwiftUI

/// Shown when the library holds no screenshots at all — there is nothing to
/// summarize yet.
struct EmptyOverviewView: View {
    var body: some View {
        ContentUnavailableView {
            Label(Strings.Triage.emptyTitle, systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(Strings.Triage.emptyMessage)
        }
    }
}
