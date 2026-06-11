//
//  OCRResult.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 10/06/26.
//

import Foundation

struct OCRResult: Sendable, Equatable {
    let screenshotID: Screenshot.ID
    let lines: [OCRLine]

    var isEmpty: Bool { lines.isEmpty }

    /// Newline-joined transcript in reading order.
    var transcript: String {
        lines.map(\.text).joined(separator: "\n")
    }
}
