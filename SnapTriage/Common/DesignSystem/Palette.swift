//
//  Palette.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import SwiftUI

/// Every colour the app draws with. Screens read from here rather than
/// re-declaring their own tokens, so a change lands everywhere at once.
enum Palette {

    // MARK: Surfaces

    static let background = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let accent = Color("AccentColor")
    static let surfaceFill = Color.white.opacity(0.05)
    static let cardStroke = Color.white.opacity(0.08)

    // MARK: Verdicts

    /// Worth keeping.
    static let keep = Color.blue
    /// Safe to delete, and the destructive action colour.
    static let delete = Color.red
    /// Needs review — deliberately neither keep nor delete.
    static let review = Color.orange
    /// Pending classification, before any verdict exists.
    static let neutral = Color.secondary

    // MARK: Controls

    /// Saturated variants for the triage buttons, which sit on black and need
    /// more weight than the flat verdict colours give them.
    static let controlKeep = Color(red: 0.08, green: 0.43, blue: 0.90)
    static let controlDelete = Color(red: 0.88, green: 0.20, blue: 0.29)
    /// Violet identifies a reversible action without borrowing keep/delete semantics.
    static let controlUndo = Color(red: 0.48, green: 0.38, blue: 0.95)
}
