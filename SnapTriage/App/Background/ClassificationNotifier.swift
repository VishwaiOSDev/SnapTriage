//
//  ClassificationNotifier.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 13/07/26.
//

import Foundation
import UserNotifications

/// Whether a completion notification actually reached the user, was
/// intentionally suppressed, or must be retried later.

@MainActor
protocol ClassificationNotifying {
    func requestAuthorizationIfNeeded() async throws
    func notifyReady(count: Int) async throws -> ClassificationNotificationDelivery
}

enum ClassificationNotificationDelivery {
    case delivered
    case suppressed
    case deferred
}

@MainActor
struct ClassificationNotifier: ClassificationNotifying {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() async throws {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notifyReady(count: Int) async throws -> ClassificationNotificationDelivery {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            return .deferred
        default:
            return .suppressed
        }

        let content = UNMutableNotificationContent()
        content.title = String(
            localized: "notification.classificationReady.title",
            defaultValue: "Screenshots ready to triage"
        )
        content.body = String(
            localized: "notification.classificationReady.body",
            defaultValue: "\(count) screenshots have been sorted. Open SnapTriage to review them."
        )
        content.sound = .default
        content.userInfo = ["destination": "triage"]

        let request = UNNotificationRequest(
            identifier: "classification-ready",
            content: content,
            trigger: nil
        )
        try await center.add(request)
        return .delivered
    }
}
