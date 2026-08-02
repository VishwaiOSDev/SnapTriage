//
//  LoadTriageProgressUseCase.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 02/07/26.
//

import Foundation

/// Restores a triage pass already in flight: counts the stored verdicts for the
/// loaded deck and reports which cards already have one, so a relaunched app
/// resumes where the user left off instead of replaying swiped cards. Choosing
/// *which* undecided card to surface is the deck's job, not this one's.
struct LoadTriageProgressUseCase {

    struct Progress: Equatable {
        let keptCount: Int
        let markedCount: Int
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
        return Progress(
            keptCount: kept,
            markedCount: marked,
            decidedIDs: decided
        )
    }
}
