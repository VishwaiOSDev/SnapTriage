//
//  AppRootView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

/// The app's single screen graph: Overview at the root, Review pushed on top of
/// it, and Triage presented over everything as a focused session.
struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var composition: AppComposition
    @State private var overviewModel: OverviewViewModel
    @State private var triageModel: TriageViewModel
    @State private var reviewModel: ReviewViewModel
    @State private var categoriesModel: CategoriesViewModel
    @State private var settingsModel: SettingsViewModel
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
        _categoriesModel = State(initialValue: composition.makeCategories())
        _settingsModel = State(initialValue: composition.makeSettings())
        _navigation = State(initialValue: navigation)
        self.backgroundCoordinator = backgroundCoordinator
    }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.path) {
            OverviewView(
                viewModel: overviewModel,
                onStartTriage: { navigation.presentTriage() },
                onOpenReview: { navigation.show(.review(.triage)) },
                onOpenCategories: { navigation.show(.categories) },
                onOpenSettings: { navigation.show(.settings) }
            )
            .navigationDestination(for: AppNavigation.Route.self) { route in
                switch route {
                case .review(.triage):
                    ReviewView(viewModel: reviewModel)
                case .review(.category(let category)):
                    // A scoped Review gets its own model. Reusing the inbox's
                    // would hand a category visit the inbox's selection — and
                    // give it back changed.
                    ReviewView(viewModel: composition.makeReview(scope: .category(category)))
                case .categories:
                    CategoriesView(
                        viewModel: categoriesModel,
                        onOpenCategory: { navigation.showCategory($0) }
                    )
                case .settings:
                    SettingsView(viewModel: settingsModel)
                }
            }
        }
        .fullScreenCover(isPresented: $navigation.isTriagePresented) {
            TriageView(
                viewModel: triageModel,
                onReview: { navigation.finishToReview() },
                onBulkTriage: { navigation.finishToCategories() }
            )
        }
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
        .onChange(of: overviewModel.isClassifying, initial: true) { _, isClassifying in
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
private struct AppRootView_Previews: PreviewProvider {
    static var previews: some View {
        makePreview()
    }

    private static func makePreview() -> some View {
        let composition = AppComposition()
        let navigation = AppNavigation()
        return AppRootView(
            composition: composition,
            navigation: navigation,
            backgroundCoordinator: composition.makeBackgroundClassificationCoordinator(navigation: navigation)
        )
    }
}
#endif
