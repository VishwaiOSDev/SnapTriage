//
//  ContentView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

struct ContentView: View {
    @State private var overviewModel = OverviewComposition.make(router: SystemOverviewRouter())
    @State private var triageModel = TriageComposition.make(router: SystemTriageRouter())
    @State private var selection: OverviewTab = .overview

    var body: some View {
        TabView(selection: $selection) {
            Tab(OverviewTab.overview.title, systemImage: OverviewTab.overview.systemImage, value: .overview) {
                OverviewView(viewModel: overviewModel) { selection = .triage }
            }
            Tab(OverviewTab.triage.title, systemImage: OverviewTab.triage.systemImage, value: .triage) {
                TriageView(viewModel: triageModel)
            }
            Tab(OverviewTab.review.title, systemImage: OverviewTab.review.systemImage, value: .review) {
                ReviewPlaceholderView()
            }
        }
        .tint(.blue)
        .preferredColorScheme(.dark)
    }
}

private struct ReviewPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            Strings.Overview.tabReview,
            systemImage: "trash",
            description: Text(Strings.Overview.reviewComingSoon)
        )
    }
}

#Preview {
    ContentView()
}
