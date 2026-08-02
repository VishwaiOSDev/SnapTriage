//
//  DecisionStamp.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

/// Tinder-style corner stamp that fades in as a card travels toward a verdict.
struct DecisionStamp: View {
    let text: String
    let color: Color
    let angle: Double

    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .heavy))
            .tracking(2)
            .foregroundStyle(color)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
    }
}
