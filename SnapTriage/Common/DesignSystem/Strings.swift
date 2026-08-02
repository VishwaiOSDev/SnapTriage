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
        static func analyzingWithEstimate(_ current: String, _ total: String, _ remaining: String) -> String {
            String(localized: .overviewAnalyzingWithEstimate(current, total, remaining))
        }
        static let analyzingContinuesInBackground = String(localized: .overviewAnalyzingContinuesInBackground)
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
        static func deleteButton(_ count: String) -> String { String(localized: .reviewDeleteButton(count)) }
        static let reclaimableHeadline = String(localized: .reviewReclaimableHeadline)
        static func selectionCaption(_ selected: String, _ total: String) -> String { String(localized: .reviewSelectionCaption(selected, total)) }
        static let deleting = String(localized: .reviewDeleting)
        static let emptyTitle = String(localized: .reviewEmptyTitle)
        static let emptyMessage = String(localized: .reviewEmptyMessage)
        static let deletionFailed = String(localized: .reviewDeletionFailed)
        static let markedSectionTitle = String(localized: .reviewMarkedSectionTitle)
        static func markedSectionSubtitle(_ count: String) -> String { String(localized: .reviewMarkedSectionSubtitle(count)) }
        static let suggestedSectionTitle = String(localized: .reviewSuggestedSectionTitle)
        static func suggestedSectionSubtitle(_ count: String, _ size: String) -> String {
            String(localized: .reviewSuggestedSectionSubtitle(count, size))
        }
        static let selectAll = String(localized: .reviewSelectAll)
        static let deselectAll = String(localized: .reviewDeselectAll)
        static let summaryLead = String(localized: .reviewSummaryLead)
        static func summaryCount(_ count: String) -> String { String(localized: .reviewSummaryCount(count)) }
        static func summaryFreeUp(_ size: String) -> String { String(localized: .reviewSummaryFreeUp(size)) }
        static let summaryEmptyTitle = String(localized: .reviewSummaryEmptyTitle)
        static let summaryEmptyDetail = String(localized: .reviewSummaryEmptyDetail)
        static let recoveryNote = String(localized: .reviewRecoveryNote)
        static func deleteSubtitle(_ size: String) -> String { String(localized: .reviewDeleteSubtitle(size)) }
    }

    enum Categories {
        static let title = String(localized: .categoriesTitle)
        static func headline(_ count: String) -> String { String(localized: .categoriesHeadline(count)) }
        static let subheadline = String(localized: .categoriesSubheadline)
        static func rowDetail(_ count: String, _ size: String) -> String { String(localized: .categoriesRowDetail(count, size)) }
        static func actionTitle(_ category: String) -> String { String(localized: .categoriesActionTitle(category)) }
        static func actionMessage(_ size: String) -> String { String(localized: .categoriesActionMessage(size)) }
        static func markAll(_ count: String) -> String { String(localized: .categoriesMarkAll(count)) }
        static func keepAll(_ count: String) -> String { String(localized: .categoriesKeepAll(count)) }
        static func appliedMarked(_ count: String, _ category: String) -> String { String(localized: .categoriesAppliedMarked(count, category)) }
        static func appliedKept(_ count: String, _ category: String) -> String { String(localized: .categoriesAppliedKept(count, category)) }
        static func stillAnalyzing(_ count: String) -> String { String(localized: .categoriesStillAnalyzing(count)) }
        static let safetyNote = String(localized: .categoriesSafetyNote)
        static let emptyTitle = String(localized: .categoriesEmptyTitle)
        static let emptyMessage = String(localized: .categoriesEmptyMessage)
    }

    enum Settings {
        static let title = String(localized: .settingsTitle)
        static let cardsSection = String(localized: .settingsCardsSection)
        static let imageModeTitle = String(localized: .settingsImageModeTitle)
        static let imageModeFit = String(localized: .settingsImageModeFit)
        static let imageModeFill = String(localized: .settingsImageModeFill)
        static let imageModeFootnote = String(localized: .settingsImageModeFootnote)
        static let photosSection = String(localized: .settingsPhotosSection)
        static let photoAccessTitle = String(localized: .settingsPhotoAccessTitle)
        static let accessFull = String(localized: .settingsAccessFull)
        static let accessLimited = String(localized: .settingsAccessLimited)
        static let accessDenied = String(localized: .settingsAccessDenied)
        static let accessRestricted = String(localized: .settingsAccessRestricted)
        static let accessNotDetermined = String(localized: .settingsAccessNotDetermined)
        static let notificationsSection = String(localized: .settingsNotificationsSection)
        static let notificationsTitle = String(localized: .settingsNotificationsTitle)
        static let notificationsFootnote = String(localized: .settingsNotificationsFootnote)
        static let statusOn = String(localized: .settingsStatusOn)
        static let statusOff = String(localized: .settingsStatusOff)
        static let storageSection = String(localized: .settingsStorageSection)
        static let cachedAnalysisTitle = String(localized: .settingsCachedAnalysisTitle)
        static func cachedAnalysisValue(_ count: String) -> String { String(localized: .settingsCachedAnalysisValue(count)) }
        static let clearCache = String(localized: .settingsClearCache)
        static let clearCacheFootnote = String(localized: .settingsClearCacheFootnote)
        static let clearCacheConfirmTitle = String(localized: .settingsClearCacheConfirmTitle)
        static let clearCacheConfirmMessage = String(localized: .settingsClearCacheConfirmMessage)
        static let clearCacheConfirm = String(localized: .settingsClearCacheConfirm)
        static let privacySection = String(localized: .settingsPrivacySection)
        static let privacyStatement = String(localized: .settingsPrivacyStatement)
        static func version(_ version: String) -> String { String(localized: .settingsVersion(version)) }
    }

    enum Access {
        static let title = String(localized: .accessTitle)
        static let openSettings = String(localized: .accessOpenSettings)
        static let retry = String(localized: .accessRetry)
        static let primerTitle = String(localized: .accessPrimerTitle)
        static let primerMessage = String(localized: .accessPrimerMessage)
        static let primerContinue = String(localized: .accessPrimerContinue)
        static let primerFootnote = String(localized: .accessPrimerFootnote)
        static let primerOnDeviceTitle = String(localized: .accessPrimerOnDeviceTitle)
        static let primerOnDeviceDetail = String(localized: .accessPrimerOnDeviceDetail)
        static let primerNoDeleteTitle = String(localized: .accessPrimerNoDeleteTitle)
        static let primerNoDeleteDetail = String(localized: .accessPrimerNoDeleteDetail)
        static let primerScreenshotsOnlyTitle = String(localized: .accessPrimerScreenshotsOnlyTitle)
        static let primerScreenshotsOnlyDetail = String(localized: .accessPrimerScreenshotsOnlyDetail)
        static let limitedTitle = String(localized: .accessLimitedTitle)
        static let limitedMessage = String(localized: .accessLimitedMessage)
        static let limitedAction = String(localized: .accessLimitedAction)
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
