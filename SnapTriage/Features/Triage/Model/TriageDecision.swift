//
//  TriageDecision.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/07/26.
//

import Foundation

/// The user's swipe verdict for a screenshot. Nothing is deleted here —
/// `markForDeletion` only queues the screenshot for the Review screen,
/// where the actual batch deletion happens.
enum TriageDecision: Equatable, Sendable {
    case keep
    case markForDeletion
}
