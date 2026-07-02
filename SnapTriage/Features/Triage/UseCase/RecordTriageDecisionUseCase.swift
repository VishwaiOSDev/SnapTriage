//
//  RecordTriageDecisionUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/07/26.
//

import Foundation

/// Persists a swipe verdict. Deliberately does not touch the photo library:
/// deletion is deferred to the Review screen, which reads the same store.
struct RecordTriageDecisionUseCase {

    let store: TriageDecisionStore

    func execute(_ decision: TriageDecision, for id: Screenshot.ID) {
        store.save(decision, for: id)
    }
}
