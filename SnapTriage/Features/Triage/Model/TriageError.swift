//
//  TriageError.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

enum TriageError: Error, Equatable {
    case photoAccessDenied
    case photoAccessRestricted
    case ocrFailed
    /// The user dismissed the system delete-confirmation sheet. Not a failure —
    /// callers should treat it as a no-op rather than surfacing an error.
    case deletionCancelled
    /// Deletion was attempted but PhotoKit reported a failure.
    case deletionFailed
}
