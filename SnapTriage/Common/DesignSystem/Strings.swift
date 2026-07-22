//
//  Strings.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

/// Centralized user-facing copy backed by Localizable.xcstrings generated symbols.
enum Strings {
    enum Overview {
        static let title = String(localized: .overviewTitle)
        static let privacy = String(localized: .overviewPrivacy)
        static let privacyLead = String(localized: .overviewPrivacyLead)
        static let reclaimableHeadline = String(localized: .overviewReclaimableHeadline)
        static func heroCaption(_ count: String) -> String { String(localized: .overviewHeroCaption(count)) }
        static let usefulTitle = String(localized: .overviewUsefulTitle)
        static let safeToDeleteTitle = String(localized: .overviewSafeToDeleteTitle)
        static let reclaimableTitle = String(localized: .overviewReclaimableTitle)
        static let startTriage = String(localized: .overviewStartTriage)
        static let startTriageHelper = String(localized: .overviewStartTriageHelper)
        static func analyzing(_ current: String, _ total: String) -> String { String(localized: .overviewAnalyzing(current, total)) }
        static let onDeviceTitle = String(localized: .overviewOnDeviceTitle)
        static let onDeviceSubtitle = String(localized: .overviewOnDeviceSubtitle)
        static let intelligentTitle = String(localized: .overviewIntelligentTitle)
        static let intelligentSubtitle = String(localized: .overviewIntelligentSubtitle)
        static let settings = String(localized: .overviewSettings)
    }

    enum Triage {
        static let title = String(localized: .triageTitle)
        static let loading = String(localized: .triageLoading)
        static let emptyTitle = String(localized: .triageEmptyTitle)
        static let emptyMessage = String(localized: .triageEmptyMessage)
        static func progress(_ current: String, _ total: String) -> String { String(localized: .triageProgress(current, total)) }
        static let keep = String(localized: .triageKeep)
        static let delete = String(localized: .triageDelete)
        static let undo = String(localized: .triageUndo)
        static let keepBadge = String(localized: .triageKeepBadge)
        static let deleteBadge = String(localized: .triageDeleteBadge)
        static let swipeRightHint = String(localized: .triageSwipeRightHint)
        static let swipeLeftHint = String(localized: .triageSwipeLeftHint)
        static let close = String(localized: .triageClose)
        static let more = String(localized: .triageMore)
        static let startOver = String(localized: .triageStartOver)
        static let restartTriage = String(localized: .triageRestartTriage)
        static let startOverConfirmTitle = String(localized: .triageStartOverConfirmTitle)
        static let startOverConfirmMessage = String(localized: .triageStartOverConfirmMessage)
        static let cancel = String(localized: .triageCancel)
        static let fitImage = String(localized: .triageFitImage)
        static let fillImage = String(localized: .triageFillImage)
        static let doneTitle = String(localized: .triageDoneTitle)
        static func doneMessage(_ kept: String, _ marked: String) -> String { String(localized: .triageDoneMessage(kept, marked)) }
        static let doneHint = String(localized: .triageDoneHint)
        static let safeToDelete = String(localized: .triageSafeToDelete)
        static let worthKeeping = String(localized: .triageWorthKeeping)
        static let needsReview = String(localized: .triageNeedsReview)
        static let analyzing = String(localized: .triageAnalyzing)
        static func today(_ time: String) -> String { String(localized: .triageToday(time)) }
        static func yesterday(_ time: String) -> String { String(localized: .triageYesterday(time)) }
    }

    enum Review {
        static let title = String(localized: .reviewTitle)
        static let reclaimableHeadline = String(localized: .reviewReclaimableHeadline)
        static func selectionCaption(_ selected: String, _ total: String) -> String { String(localized: .reviewSelectionCaption(selected, total)) }
        static func deleteButton(_ count: String, _ size: String) -> String { String(localized: .reviewDeleteButton(count, size)) }
        static let deleting = String(localized: .reviewDeleting)
        static let emptyTitle = String(localized: .reviewEmptyTitle)
        static let emptyMessage = String(localized: .reviewEmptyMessage)
        static let deletionFailed = String(localized: .reviewDeletionFailed)
    }

    enum Access {
        static let title = String(localized: .accessTitle)
        static let back = String(localized: .accessBack)
        static let openSettings = String(localized: .accessOpenSettings)
        static let retry = String(localized: .accessRetry)
    }

    enum Transcript {
        static let title = String(localized: .transcriptTitle)
        static let recognizing = String(localized: .transcriptRecognizing)
        static let empty = String(localized: .transcriptEmpty)
        static let failed = String(localized: .transcriptFailed)
        static let done = String(localized: .transcriptDone)
    }

    enum Category {
        static let game = String(localized: .categoryGame)
        static let receipt = String(localized: .categoryReceipt)
        static let code = String(localized: .categoryCode)
        static let conversation = String(localized: .categoryConversation)
        static let article = String(localized: .categoryArticle)
        static let social = String(localized: .categorySocial)
        static let location = String(localized: .categoryLocation)
        static let otp = String(localized: .categoryOtp)
        static let travel = String(localized: .categoryTravel)
        static let event = String(localized: .categoryEvent)
        static let email = String(localized: .categoryEmail)
        static let identity = String(localized: .categoryIdentity)
        static let document = String(localized: .categoryDocument)
        static let photo = String(localized: .categoryPhoto)
        static let alarm = String(localized: .categoryAlarm)
        static let entertainment = String(localized: .categoryEntertainment)
        static let finance = String(localized: .categoryFinance)
        static let shopping = String(localized: .categoryShopping)
        static let settings = String(localized: .categorySettings)
        static let reminder = String(localized: .categoryReminder)
        static let other = String(localized: .categoryOther)
    }

    enum Error {
        static let accessDenied = String(localized: .errorAccessDenied)
        static let accessRestricted = String(localized: .errorAccessRestricted)
        static let generic = String(localized: .errorGeneric)
    }
}
