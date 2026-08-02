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
    /// The pushed destinations. Triage isn't here — it's a full-screen
    /// session, not a peer place, so it presents rather than pushes.
    enum Route: Hashable {
        /// Review is scoped: the triage inbox from Overview, one category when
        /// the user drills into a bucket from the category list.
        case review(ReviewScope)
        case categories
        case settings
    }

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

    /// Show a destination as a push on the Overview stack.
    func show(_ route: Route) {
        path = [route]
    }

    /// Leave the triage session for bulk category actions.
    func finishToCategories() {
        isTriagePresented = false
        path = [.categories]
    }

    /// Leave the triage session and land the user on Review to confirm deletions.
    /// Dismisses the cover and pushes Review underneath in one step.
    func finishToReview() {
        isTriagePresented = false
        path = [.review(.triage)]
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
