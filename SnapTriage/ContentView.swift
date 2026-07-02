//
//  ContentView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var composition: AppComposition
    @State private var overviewModel: OverviewViewModel
    @State private var triageModel: TriageViewModel
    @State private var reviewModel: ReviewViewModel
    @State private var selection: OverviewTab = .overview

    init() {
        let composition = AppComposition()
        _composition = State(initialValue: composition)
        _overviewModel = State(initialValue: composition.makeOverview())
        _triageModel = State(initialValue: composition.makeTriage())
        _reviewModel = State(initialValue: composition.makeReview())
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(OverviewTab.overview.title, systemImage: OverviewTab.overview.systemImage, value: .overview) {
                OverviewView(viewModel: overviewModel) { selection = .triage }
            }
            Tab(OverviewTab.triage.title, systemImage: OverviewTab.triage.systemImage, value: .triage) {
                TriageView(viewModel: triageModel) { selection = .overview }
            }
            Tab(OverviewTab.review.title, systemImage: OverviewTab.review.systemImage, value: .review) {
                ReviewView(viewModel: reviewModel)
            }
        }
        .tint(.blue)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            // The stores write behind a debounce; backgrounding is the last
            // reliable moment to force pending verdicts out before a kill.
            if phase == .background { composition.flushStores() }
        }
    }
}

#Preview {
    ContentView()
}
