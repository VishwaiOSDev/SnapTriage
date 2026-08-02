//
//  PrivacyPillView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import SwiftUI

/// States up front that nothing leaves the device — the first thing a user
/// wonders when an app asks for their whole screenshot library.
struct PrivacyPillView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.accent)
            Text(Strings.Overview.privacyLead)
                .foregroundStyle(.white)
                .fontWeight(.semibold)
            + Text(" " + privacyTrailing)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .liquidGlass(in: Capsule())
    }

    private var privacyTrailing: String {
        Strings.Overview.privacy
            .replacingOccurrences(of: Strings.Overview.privacyLead + " ", with: "")
    }
}
