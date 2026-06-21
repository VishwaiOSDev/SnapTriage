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

    enum Transcript {
        static let title = "Recognized Text"
        static let recognizing = "Reading text…"
        static let empty = "No text was recognized in this screenshot."
        static let failed = "Couldn't read text from this screenshot."
        static let done = "Done"
    }

    enum Category {
        static let receipt = "Receipt"
        static let code = "Code"
        static let conversation = "Conversation"
        static let article = "Article"
        static let social = "Social"
        static let location = "Location"
        static let otp = "Verification Code"
        static let travel = "Travel"
        static let event = "Event"
        static let email = "Email"
        static let identity = "ID"
        static let document = "Document"
        static let photo = "Photo"
        static let other = "Other"
    }

    enum Error {
        static let accessDenied = "SnapTriage needs access to your photos to find and triage your screenshots. You can grant access in Settings."
        static let accessRestricted = "Photo access is restricted on this device, so screenshots can't be loaded."
        static let generic = "Something went wrong while loading your screenshots."
    }
}
