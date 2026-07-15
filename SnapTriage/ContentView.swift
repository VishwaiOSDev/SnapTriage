//
//  ContentView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppNavigation {
    var selection: OverviewTab = .overview

    @ObservationIgnored private var isSceneActive = false
    @ObservationIgnored private var pendingSelection: OverviewTab?

    /// Notification responses can arrive before SwiftUI has connected an
    /// active scene. Queue the destination instead of mutating TabView during
    /// launch or scene restoration.
    func requestSelection(_ selection: OverviewTab) {
        guard isSceneActive else {
            pendingSelection = selection
            return
        }
        self.selection = selection
    }

    func sceneDidBecomeActive() {
        isSceneActive = true
        guard let pendingSelection else { return }
        self.pendingSelection = nil
        selection = pendingSelection
    }

    func sceneDidLeaveActive() {
        isSceneActive = false
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var composition: AppComposition
    @State private var overviewModel: OverviewViewModel
    @State private var triageModel: TriageViewModel
    @State private var reviewModel: ReviewViewModel
    @State private var navigation: AppNavigation
    private let backgroundCoordinator: BackgroundClassificationCoordinator

    init(
        composition: AppComposition,
        navigation: AppNavigation,
        backgroundCoordinator: BackgroundClassificationCoordinator
    ) {
        _composition = State(initialValue: composition)
        _overviewModel = State(initialValue: composition.makeOverview())
        _triageModel = State(initialValue: composition.makeTriage())
        _reviewModel = State(initialValue: composition.makeReview())
        _navigation = State(initialValue: navigation)
        self.backgroundCoordinator = backgroundCoordinator
    }

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.selection) {
            Tab(OverviewTab.overview.title, systemImage: OverviewTab.overview.systemImage, value: .overview) {
                OverviewView(viewModel: overviewModel) { navigation.selection = .triage }
            }
            Tab(OverviewTab.triage.title, systemImage: OverviewTab.triage.systemImage, value: .triage) {
                TriageView(viewModel: triageModel) { navigation.selection = .overview }
            }
            Tab(OverviewTab.review.title, systemImage: OverviewTab.review.systemImage, value: .review) {
                ReviewView(viewModel: reviewModel)
            }
        }
        .tint(.blue)
        .preferredColorScheme(.dark)
        .onChange(of: overviewModel.state.isClassifying, initial: true) { _, isClassifying in
            // Only prompt after the user granted Photos access and actual work
            // exists. This keeps two system permission sheets from competing at
            // first launch and avoids asking users whose library is already warm.
            guard isClassifying else { return }
            Task { await backgroundCoordinator.requestNotificationAuthorization() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                navigation.sceneDidLeaveActive()
                // The stores write behind a debounce; backgrounding is the last
                // reliable moment to force pending verdicts out before a kill. It's
                // also when we bridge the in-flight pass and schedule the suspended
                // full-library pass.
                composition.flushStores()
                backgroundCoordinator.handleAppDidBackground()
            case .active:
                navigation.sceneDidBecomeActive()
                backgroundCoordinator.handleAppWillEnterForeground()
            case .inactive:
                navigation.sceneDidLeaveActive()
            @unknown default:
                navigation.sceneDidLeaveActive()
            }
        }
    }
}

#if DEBUG
@MainActor
private struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        makePreview()
    }

    private static func makePreview() -> some View {
        let composition = AppComposition()
        let navigation = AppNavigation()
        return ContentView(
            composition: composition,
            navigation: navigation,
            backgroundCoordinator: composition.makeBackgroundClassificationCoordinator(navigation: navigation)
        )
    }
}
#endif
