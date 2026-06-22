//
//  ScreenshotDisposition.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation

/// Whether a screenshot is worth keeping or a safe deletion candidate.
/// Drives the Overview "Useful" vs "Safe to delete" split.
enum ScreenshotDisposition: Equatable {
    case useful
    case safeToDelete
}
