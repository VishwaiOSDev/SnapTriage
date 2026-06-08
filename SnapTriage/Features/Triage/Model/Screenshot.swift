//
//  Screenshot.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation

struct Screenshot: Identifiable, Equatable, Sendable {
    /// `PHAsset.localIdentifier` — stable key for thumbnails, later OCR cache and deletion.
    let id: String
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
}
