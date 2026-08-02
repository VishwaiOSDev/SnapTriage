//
//  AppNavigation.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

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
