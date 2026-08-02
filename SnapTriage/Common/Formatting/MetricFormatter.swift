//
//  MetricFormatter.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import Foundation

/// Formats the two quantities every screen displays: counts of screenshots and
/// byte sizes. Shared so "1,204" and "1.8 MB" read identically everywhere.
enum MetricFormatter {

    static func count(_ value: Int) -> String {
        counter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static let counter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}
