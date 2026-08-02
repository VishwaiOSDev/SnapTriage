//
//  ForegroundNotificationPresenter.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 13/07/26.
//

import Foundation
import UserNotifications

/// Presents the completion banner in the foreground and routes notification
/// taps directly to the Triage tab.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let onOpenTriage: @MainActor @Sendable () -> Void

    init(onOpenTriage: @escaping @MainActor @Sendable () -> Void) {
        self.onOpenTriage = onOpenTriage
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let shouldOpenTriage =
            request.identifier == NotificationKey.readyIdentifier &&
            request.content.userInfo[NotificationKey.destination] as? String == NotificationKey.triageDestination

        // Never make UserNotifications wait for the main actor while SwiftUI is
        // creating/restoring its scene. Acknowledge the response synchronously;
        // AppNavigation will apply the route once the scene becomes active.
        completionHandler()
        guard shouldOpenTriage else { return }
        Task { @MainActor [onOpenTriage] in
            onOpenTriage()
        }
    }
}
