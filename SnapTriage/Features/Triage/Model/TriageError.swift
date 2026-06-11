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
}
