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
///
/// Raw values are the on-disk schema of the persisted decision store;
/// renaming a case is a format change.
enum TriageDecision: String, Codable, Equatable, Sendable {
    case keep
    case markForDeletion
}
