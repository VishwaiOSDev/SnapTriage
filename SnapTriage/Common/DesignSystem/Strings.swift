//
//  Strings.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

enum Strings {
    enum Overview {
        static let title = "Screenshot Triage"
        static let privacy = "All on-device. Your data stays private."
        static let privacyLead = "All on-device."
        static let reclaimableHeadline = "reclaimable"
        static let heroCaption = "Found in %@ screenshots"

        static let usefulTitle = "Useful"
        static let safeToDeleteTitle = "Safe to delete"
        static let reclaimableTitle = "Reclaimable"

        static let startTriage = "Start triage"
        static let startTriageHelper = "Swipe through to keep what matters."
        static let analyzing = "Analyzing %@ of %@…"

        static let onDeviceTitle = "100% on-device"
        static let onDeviceSubtitle = "Nothing is uploaded or shared"
        static let intelligentTitle = "Intelligent triage"
        static let intelligentSubtitle = "Surfaces the one detail that matters"

        static let tabOverview = "Overview"
        static let tabTriage = "Triage"
        static let tabReview = "Review"

        static let settings = "Settings"
    }

    enum Triage {
        static let title = "Triage"
        static let loading = "Loading screenshots…"
        static let emptyTitle = "No Screenshots"
        static let emptyMessage = "Screenshots you capture will show up here, ready to triage."
    }

    enum Review {
        static let title = "Review"
        static let reclaimableHeadline = "to free up"
        static let selectionCaption = "%@ of %@ selected"
        static let deleteButton = "Delete %@ · Free %@"
        static let deleting = "Deleting…"
        static let emptyTitle = "Nothing to Review"
        static let emptyMessage = "Screenshots marked safe to delete will show up here for a final check before they're removed."
        static let deletionFailed = "Couldn't delete the selected screenshots. Please try again."
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
