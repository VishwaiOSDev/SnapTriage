//
//  CardImageMode.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

/// How a screenshot is fitted inside a triage card. A presentation preference,
/// not domain state: fit is the safer default, since the user sees the whole
/// screenshot unless they explicitly choose crop.
enum CardImageMode: String {
    case fit
    case fill

    var toggled: Self { self == .fit ? .fill : .fit }
}
