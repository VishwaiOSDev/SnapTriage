//
//  OCRLine.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 10/06/26.
//

import CoreGraphics

struct OCRLine: Codable, Sendable, Equatable {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}
