//
//  SnapTriageApp.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

@main
struct SnapTriageApp: App {
    @State private var composition: AppComposition
    @State private var navigation: AppNavigation
    private let backgroundCoordinator: BackgroundClassificationCoordinator

    init() {
        let composition = AppComposition()
        let navigation = AppNavigation()
        let coordinator = composition.makeBackgroundClassificationCoordinator(navigation: navigation)
        // Register the launch handler synchronously during launch, before the
        // first scene connects — the system requires the task identifier to be
        // claimed before `didFinishLaunching` returns.
        coordinator.registerLaunchHandler()
        _composition = State(initialValue: composition)
        _navigation = State(initialValue: navigation)
        backgroundCoordinator = coordinator
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                composition: composition,
                navigation: navigation,
                backgroundCoordinator: backgroundCoordinator
            )
        }
    }
}
