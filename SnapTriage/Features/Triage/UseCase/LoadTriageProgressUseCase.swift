//
//  LoadTriageProgressUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 02/07/26.
//

import Foundation

/// Restores a triage pass already in flight: counts the stored verdicts for
/// the loaded deck and finds the first card without one, so a relaunched app
/// resumes where the user left off instead of replaying swiped cards.
struct LoadTriageProgressUseCase {

    struct Progress: Equatable {
        let keptCount: Int
        let markedCount: Int
        /// Index of the first screenshot without a verdict; `screenshots.count`
        /// when every card is decided, which surfaces the finished screen.
        /// Decided cards can sit *after* this index — the deck sorts newest
        /// first, so a screenshot taken mid-pass appears above swiped cards.
        let firstUndecidedIndex: Int
        /// The deck entries that already have a verdict; the deck skips these
        /// when advancing.
        let decidedIDs: Set<Screenshot.ID>
    }

    let store: TriageDecisionStore

    func execute(for screenshots: [Screenshot]) -> Progress {
        let verdicts = store.allDecisions()
        var kept = 0
        var marked = 0
        var decided: Set<Screenshot.ID> = []
        for screenshot in screenshots {
            switch verdicts[screenshot.id] {
            case .keep:            kept += 1
            case .markForDeletion: marked += 1
            case nil:              continue
            }
            decided.insert(screenshot.id)
        }
        let firstUndecided = screenshots.firstIndex { verdicts[$0.id] == nil } ?? screenshots.count
        return Progress(
            keptCount: kept,
            markedCount: marked,
            firstUndecidedIndex: firstUndecided,
            decidedIDs: decided
        )
    }
}
