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
        }
        .tint(.blue)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
