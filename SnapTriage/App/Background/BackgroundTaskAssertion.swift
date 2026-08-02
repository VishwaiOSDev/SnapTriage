//
//  BackgroundTaskAssertion.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 13/07/26.
//

import UIKit

/// A single UIKit background-time assertion for the brief transition from an
/// active scene to suspension. This is best effort and never substitutes for a
/// BGProcessingTask.
@MainActor
final class BackgroundTaskAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private let application: UIApplication

    init(application: UIApplication) {
        self.application = application
    }

    convenience init() {
        self.init(application: .shared)
    }

    func begin(name: String, onExpiration: @escaping @MainActor () -> Void) {
        guard identifier == .invalid else { return }
        identifier = application.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor [weak self] in
                onExpiration()
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        application.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
