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
        bytesFormatter.string(fromByteCount: Int64(bytes))
    }

    /// Short "when was this taken" label for a grid tile: the time for today,
    /// the word for yesterday, an abbreviated date for anything older.
    static func timestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return Strings.Review.yesterday
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private static let counter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    // The class method spells zero as "Zero KB", which read as a bug on the
    // Review screen the moment the user deselected everything.
    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}
