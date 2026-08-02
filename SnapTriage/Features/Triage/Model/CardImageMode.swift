//
//  CardImageMode.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

/// How a screenshot is framed on a triage card. A presentation preference, not
/// domain state: it never reaches a ViewModel, it is read straight from
/// `@AppStorage` by the deck and by Settings.
///
/// Fit is the default because it is the safer one — the user sees the whole
/// screenshot unless they explicitly choose to crop.
enum CardImageMode: String, CaseIterable {
    case fit
    case fill

    /// The `@AppStorage` key both the deck and Settings bind to.
    static let storageKey = "triage.imageDisplayMode"

    var toggled: Self { self == .fit ? .fill : .fit }

    var title: String {
        switch self {
        case .fit:  Strings.Settings.imageModeFit
        case .fill: Strings.Settings.imageModeFill
        }
    }

    var systemImage: String {
        switch self {
        case .fit:  "arrow.down.forward.and.arrow.up.backward"
        case .fill: "arrow.up.left.and.arrow.down.right"
        }
    }
}
