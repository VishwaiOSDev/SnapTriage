//
//  OverviewStatCard.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import SwiftUI

/// One figure in the summary row: an indicator, the value, and its label.
struct OverviewStatCard: View {
    let stat: TriageStat

    var body: some View {
        VStack(spacing: 8) {
            indicator
                .frame(height: 30)
            Text(stat.value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(stat.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let detail = stat.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch stat.indicator {
        case .icon(let name):
            Image(systemName: name)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Palette.accent)
        case .progress(let value):
            ProgressRing(progress: value)
                .frame(width: 30, height: 30)
        }
    }
}

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
