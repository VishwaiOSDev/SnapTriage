//
//  ClassificationCompletionStore.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 13/07/26.
//

import Foundation

/// Remembers that a completion notification is owed. The debt survives process
/// death, so a pass that finishes while notifications are still undetermined can
/// deliver on the next launch instead of being lost.
@MainActor
protocol ClassificationCompletionStoring {
    var pendingCount: Int? { get }
    func savePendingCount(_ count: Int)
    func clearPendingCount()
}

@MainActor
final class UserDefaultsClassificationCompletionStore: ClassificationCompletionStoring {
    private static let key = "classification.pendingNotificationCount"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pendingCount: Int? {
        guard defaults.object(forKey: Self.key) != nil else { return nil }
        return defaults.integer(forKey: Self.key)
    }

    func savePendingCount(_ count: Int) {
        defaults.set(count, forKey: Self.key)
    }

    func clearPendingCount() {
        defaults.removeObject(forKey: Self.key)
    }
}
