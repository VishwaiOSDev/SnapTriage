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
