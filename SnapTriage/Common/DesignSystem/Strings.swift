//
//  Strings.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

enum Strings {
    enum Triage {
        static let title = "Screenshots"
        static let loading = "Loading screenshots…"
        static let emptyTitle = "No Screenshots"
        static let emptyMessage = "Screenshots you capture will show up here, ready to triage."
    }

    enum Access {
        static let title = "Photo Access Needed"
        static let openSettings = "Open Settings"
        static let retry = "Try Again"
    }

    enum Error {
        static let accessDenied = "SnapTriage needs access to your photos to find and triage your screenshots. You can grant access in Settings."
        static let accessRestricted = "Photo access is restricted on this device, so screenshots can't be loaded."
        static let generic = "Something went wrong while loading your screenshots."
    }
}
