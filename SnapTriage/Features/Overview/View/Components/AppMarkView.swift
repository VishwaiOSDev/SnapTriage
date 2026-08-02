//
//  AppMarkView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import SwiftUI

/// Sized for the navigation bar, where the system caps item height at 28pt.
struct AppMarkView: View {
    var body: some View {
        Image(systemName: "doc.text.viewfinder")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}
