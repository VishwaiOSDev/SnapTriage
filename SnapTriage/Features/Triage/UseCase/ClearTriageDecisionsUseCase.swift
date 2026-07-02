//
//  ClearTriageDecisionsUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/07/26.
//

import Foundation

/// Wipes every recorded swipe so "Start Over" begins a genuinely fresh triage
/// pass instead of replaying stale verdicts into the Review screen.
struct ClearTriageDecisionsUseCase {

    let store: TriageDecisionStore

    func execute() {
        store.removeAll()
    }
}
