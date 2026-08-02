//
//  OverviewView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import SwiftUI

struct OverviewView: View {
    @State private var viewModel: OverviewViewModel
    private let onStartTriage: () -> Void
    private let onOpenReview: () -> Void

    init(
        viewModel: OverviewViewModel,
        onStartTriage: @escaping () -> Void,
        onOpenReview: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onStartTriage = onStartTriage
        self.onOpenReview = onOpenReview
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle(Strings.Overview.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AppMarkView()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.send(.openSettings)
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel(Strings.Overview.settings)
            }
        }
        .task { viewModel.send(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state.phase {
        case .idle, .loading:
            status { ProgressView(Strings.Triage.loading) }

        case .failed:
            status { failure }

        case .loaded:
            if viewModel.state.summary.totalCount == 0 {
                status { EmptyOverviewView() }
            } else {
                loaded
            }
        }
    }

    // Centers a non-content state in the space below the navigation bar.
    private func status<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        inner()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Spacing.screenPadding)
    }

    private var loaded: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionSpacing) {
                PrivacyPillView()
                hero
                summaryCard
                featureCard
            }
            .glassContainer()
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.sectionSpacing)
            .padding(.bottom, Spacing.sectionSpacing)
            .animation(.default, value: viewModel.state.summary)
        }
        .scrollIndicators(.hidden)
    }

    // The reclaimable figure is the reward and the door to Review: tapping it
    // takes the user straight to the final delete list, so Review needs no tab.
    private var hero: some View {
        let summary = viewModel.state.summary
        let hasReclaimable = summary.safeCount > 0
        return Button(action: onOpenReview) {
            VStack(spacing: 6) {
                VStack(spacing: 2) {
                    HeroMetricText(MetricFormatter.size(summary.reclaimableBytes), size: 72)
                    Text(Strings.Overview.reclaimableHeadline)
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .multilineTextAlignment(.center)

                HStack(spacing: 4) {
                    Text(Strings.Overview.heroCaption(MetricFormatter.count(summary.totalCount)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if hasReclaimable {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }

                if viewModel.state.isClassifying {
                    Label(
                        Strings.Overview.analyzing(
                            MetricFormatter.count(viewModel.state.classifiedCount),
                            MetricFormatter.count(summary.totalCount)
                        ),
                        systemImage: "wand.and.stars"
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summaryCard: some View {
        ZStack {
            summaryCardGlow
            GlassCard {
                VStack(spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(stats) { stat in
                            OverviewStatCard(stat: stat)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    PrimaryActionButton(
                        title: Strings.Overview.startTriage,
                        systemImage: "chevron.right",
                        action: onStartTriage
                    )

                    Text(Strings.Overview.startTriageHelper)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(Spacing.cardPadding)
            }
        }
    }

    // Give the neutral glass a real blue light source to sample. Keeping this
    // behind the material is more natural than tinting the card.
    private var summaryCardGlow: some View {
        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [
                        Palette.accent.opacity(0.24),
                        Palette.accent.opacity(0.08),
                        .clear
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: 230
                )
            )
            .blur(radius: 30)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityHidden(true)
    }

    private var featureCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                let features = viewModel.state.features
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    FeatureRowView(feature: feature) {
                        viewModel.send(.selectFeature(feature.id))
                    }
                    if index < features.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.06))
                            .padding(.leading, 64)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var failure: some View {
        ContentUnavailableView {
            Label(Strings.Access.title, systemImage: "lock.fill")
        } description: {
            Text(viewModel.state.errorMessage ?? Strings.Error.generic)
        } actions: {
            if showsOpenSettings {
                Button(Strings.Access.openSettings) { viewModel.send(.openSettings) }
                    .buttonStyle(.borderedProminent)
            }
            Button(Strings.Access.retry) { viewModel.send(.retry) }
        }
    }

    // Offer Settings only after an actual denial, not while the prompt is undetermined.
    private var showsOpenSettings: Bool {
        let auth = viewModel.state.authorization
        return !auth.canAccessLibrary && auth != .notDetermined
    }

    // MARK: - Display

    private var stats: [TriageStat] {
        let summary = viewModel.state.summary
        return [
            TriageStat(
                id: .useful,
                value: MetricFormatter.count(summary.usefulCount),
                title: Strings.Overview.usefulTitle,
                detail: MetricFormatter.size(summary.usefulBytes),
                indicator: .icon("checkmark.circle.fill")
            ),
            TriageStat(
                id: .safeToDelete,
                value: MetricFormatter.count(summary.safeCount),
                title: Strings.Overview.safeToDeleteTitle,
                detail: MetricFormatter.size(summary.safeBytes),
                indicator: .icon("square.3.layers.3d")
            ),
            TriageStat(
                id: .reclaimable,
                value: "\(Int((summary.reclaimableRatio * 100).rounded()))%",
                title: Strings.Overview.reclaimableTitle,
                detail: nil,
                indicator: .progress(summary.reclaimableRatio)
            )
        ]
    }
}


private struct PrivacyPillView: View {
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

private struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.94))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 15)
                .frame(minHeight: 56)
                .contentShape(Capsule())
        }
        .buttonStyle(PrimaryActionButtonStyle())
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Capsule()
                    .fill(Self.fill)
                    .overlay {
                        Capsule().fill(Self.sheen)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Self.rim, lineWidth: 1)
                    }
            }
            .shadow(
                color: Self.glow.opacity(configuration.isPressed ? 0.06 : 0.10),
                radius: configuration.isPressed ? 5 : 8,
                y: 2
            )
            .shadow(color: .black.opacity(0.30), radius: 4, y: 3)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }

    // Sampled from the Figma primary action reference. A diagonal transition
    // preserves its brighter leading edge and slightly deeper trailing edge.
    private static let fill = LinearGradient(
        colors: [
            Palette.accent,
            Color(red: 0.13, green: 0.41, blue: 0.87)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    private static let sheen = LinearGradient(
        colors: [.white.opacity(0.025), .clear],
        startPoint: .top,
        endPoint: .center
    )
    private static let rim = LinearGradient(
        colors: [
            Color(red: 0.31, green: 0.61, blue: 1.0).opacity(0.9),
            Color(red: 0.17, green: 0.51, blue: 0.97).opacity(0.7)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    private static let glow = Color(red: 0.08, green: 0.38, blue: 0.95)
}

private struct OverviewStatCard: View {
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

private struct FeatureRowView: View {
    let feature: FeatureHighlight
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: feature.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 34, height: 34)
                    .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(feature.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.cardPadding)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyOverviewView: View {
    var body: some View {
        ContentUnavailableView {
            Label(Strings.Triage.emptyTitle, systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(Strings.Triage.emptyMessage)
        }
    }
}

#if DEBUG
@MainActor
private struct OverviewView_Previews: PreviewProvider {
    static var previews: some View {
        makePreview()
    }

    private static func makePreview() -> some View {
        let viewModel = AppComposition().makeOverview()
        viewModel.seedForPreview(.sample)
        return NavigationStack {
            OverviewView(viewModel: viewModel, onStartTriage: {}, onOpenReview: {})
        }
        .preferredColorScheme(.dark)
    }
}
#endif
