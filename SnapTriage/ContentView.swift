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
    /// The one pushed destination. Triage isn't here — it's a full-screen
    /// session, not a peer place, so it presents rather than pushes.
    enum Route: Hashable { case review }

    /// Push stack rooted at Overview.
    var path: [Route] = []
    /// Triage runs as a focused, full-screen session with an explicit exit.
    var isTriagePresented = false

    @ObservationIgnored private var isSceneActive = false
    @ObservationIgnored private var pendingTriage = false

    /// Notification responses can arrive before SwiftUI has connected an active
    /// scene. Queue the presentation instead of mutating navigation during launch
    /// or scene restoration.
    func presentTriage() {
        guard isSceneActive else {
            pendingTriage = true
            return
        }
        isTriagePresented = true
    }

    /// Show Review as a pushed destination on the Overview stack.
    func showReview() {
        path = [.review]
    }

    /// Leave the triage session and land the user on Review to confirm deletions.
    /// Dismisses the cover and pushes Review underneath in one step.
    func finishToReview() {
        isTriagePresented = false
        path = [.review]
    }

    func sceneDidBecomeActive() {
        isSceneActive = true
        guard pendingTriage else { return }
        pendingTriage = false
        isTriagePresented = true
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
        NavigationStack(path: $navigation.path) {
            OverviewView(
                viewModel: overviewModel,
                onStartTriage: { navigation.presentTriage() },
                onOpenReview: { navigation.showReview() }
            )
            .navigationDestination(for: AppNavigation.Route.self) { route in
                switch route {
                case .review:
                    // Review carries its own header and back control, so the
                    // system bar would only double the chrome.
                    ReviewView(viewModel: reviewModel)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .fullScreenCover(isPresented: $navigation.isTriagePresented) {
            TriageView(
                viewModel: triageModel,
                onReview: { navigation.finishToReview() }
            )
        }
        .tint(Color("AccentColor"))
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
