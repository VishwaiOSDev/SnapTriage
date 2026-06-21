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
    case other

    var title: String {
        switch self {
        case .receipt:      Strings.Category.receipt
        case .code:         Strings.Category.code
        case .conversation: Strings.Category.conversation
        case .article:      Strings.Category.article
        case .social:       Strings.Category.social
        case .location:     Strings.Category.location
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
        case .other:        "square.dashed"
        }
    }
}
