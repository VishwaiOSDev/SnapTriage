//
//  ScreenshotCategory.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 20/06/26.
//

import Foundation

enum ScreenshotCategory: String, CaseIterable, Sendable, Equatable {
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
    case other

    var title: String {
        switch self {
        case .receipt:      Strings.Category.receipt
        case .code:         Strings.Category.code
        case .conversation: Strings.Category.conversation
        case .article:      Strings.Category.article
        case .social:       Strings.Category.social
        case .location:     Strings.Category.location
        case .otp:          Strings.Category.otp
        case .travel:       Strings.Category.travel
        case .event:        Strings.Category.event
        case .email:        Strings.Category.email
        case .identity:     Strings.Category.identity
        case .document:     Strings.Category.document
        case .photo:        Strings.Category.photo
        case .other:        Strings.Category.other
        }
    }

    var systemImage: String {
        switch self {
        case .receipt:      "receipt"
        case .code:         "chevron.left.forwardslash.chevron.right"
        case .conversation: "bubble.left.and.bubble.right"
        case .article:      "doc.text"
        case .social:       "heart"
        case .location:     "mappin.and.ellipse"
        case .otp:          "lock.shield"
        case .travel:       "airplane"
        case .event:        "calendar"
        case .email:        "envelope"
        case .identity:     "person.text.rectangle"
        case .document:     "doc.richtext"
        case .photo:        "photo"
        case .other:        "square.dashed"
        }
    }
}
