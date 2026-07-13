//
//  ScreenshotCategory.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation

/// Raw values are the on-disk schema of the persisted classification cache;
/// renaming a case is a format change.
///
/// This is the internal taxonomy. It is intentionally richer than the strictly
/// user-facing set — `alarm`, `entertainment`, `finance`, `shopping`,
/// `settings`, and `reminder` let the pipeline resolve screens that used to be
/// forced into a nearby wrong bucket (an alarm becoming a game, a movie screen
/// becoming an event). It never names a specific app such as Netflix or Clock.
enum ScreenshotCategory: String, CaseIterable, Codable, Sendable, Equatable {
    case game
    case receipt
    case code
    case conversation
    case article
    case social
    case location
    case otp
    case travel
    case event
    case email
    case identity
    case document
    case photo
    // Added in the cheap-first taxonomy pass.
    case alarm
    case entertainment
    case finance
    case shopping
    case settings
    case reminder
    case other

    var title: String {
        switch self {
        case .game:          Strings.Category.game
        case .receipt:       Strings.Category.receipt
        case .code:          Strings.Category.code
        case .conversation:  Strings.Category.conversation
        case .article:       Strings.Category.article
        case .social:        Strings.Category.social
        case .location:      Strings.Category.location
        case .otp:           Strings.Category.otp
        case .travel:        Strings.Category.travel
        case .event:         Strings.Category.event
        case .email:         Strings.Category.email
        case .identity:      Strings.Category.identity
        case .document:      Strings.Category.document
        case .photo:         Strings.Category.photo
        case .alarm:         Strings.Category.alarm
        case .entertainment: Strings.Category.entertainment
        case .finance:       Strings.Category.finance
        case .shopping:      Strings.Category.shopping
        case .settings:      Strings.Category.settings
        case .reminder:      Strings.Category.reminder
        case .other:         Strings.Category.other
        }
    }

    /// The category's *inherent* keep/delete leaning, before confidence is taken
    /// into account. Retention is decoupled from category: the actual disposition
    /// shown to the user is computed by ``RetentionPolicy`` from a full
    /// ``ScreenshotClassification`` (category **and** confidence), so a
    /// low-confidence guess never sends a screenshot to the delete pile.
    ///
    /// Records, credentials, financial and travel/event docs, and reminders are
    /// worth keeping; ephemeral content is safe to delete. Genuinely ambiguous
    /// buckets (`shopping`, `other`) default to needs-review.
    var baseDisposition: ScreenshotDisposition {
        switch self {
        case .receipt, .otp, .identity, .travel, .event, .document, .email, .finance, .reminder:
            .useful
        case .game, .code, .conversation, .article, .social, .location, .photo, .entertainment, .alarm, .settings:
            .safeToDelete
        case .shopping, .other:
            .needsReview
        }
    }

    var systemImage: String {
        switch self {
        case .game:          "gamecontroller.fill"
        case .receipt:       "receipt"
        case .code:          "chevron.left.forwardslash.chevron.right"
        case .conversation:  "bubble.left.and.bubble.right"
        case .article:       "doc.text"
        case .social:        "heart"
        case .location:      "mappin.and.ellipse"
        case .otp:           "lock.shield"
        case .travel:        "airplane"
        case .event:         "calendar"
        case .email:         "envelope"
        case .identity:      "person.text.rectangle"
        case .document:      "doc.richtext"
        case .photo:         "photo"
        case .alarm:         "alarm"
        case .entertainment: "film"
        case .finance:       "banknote"
        case .shopping:      "cart"
        case .settings:      "gearshape"
        case .reminder:      "checklist"
        case .other:         "square.dashed"
        }
    }
}
