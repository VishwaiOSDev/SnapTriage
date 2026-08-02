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
    private let onOpenCategories: () -> Void
    private let onOpenSettings: () -> Void

    init(
        viewModel: OverviewViewModel,
        onStartTriage: @escaping () -> Void,
        onOpenReview: @escaping () -> Void,
        onOpenCategories: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onStartTriage = onStartTriage
        self.onOpenReview = onOpenReview
        self.onOpenCategories = onOpenCategories
        self.onOpenSettings = onOpenSettings
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
                Button(action: onOpenSettings) {
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

        case .primingAccess:
            PhotoAccessPrimerView { viewModel.send(.grantAccess) }

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
                if viewModel.state.isLimitedAccess {
                    LimitedAccessBanner { viewModel.send(.addMorePhotos) }
                }
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
                    analyzingStatus
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // "Analyzing 42 of 1,204" is honest but says nothing about how long, and
    // hides the best thing about the pass: it survives the app being closed.
    private var analyzingStatus: some View {
        VStack(spacing: 3) {
            Label(analyzingText, systemImage: "wand.and.stars")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(Strings.Overview.analyzingContinuesInBackground)
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
    }

    private var analyzingText: String {
        let current = MetricFormatter.count(viewModel.state.classifiedCount)
        let total = MetricFormatter.count(viewModel.state.summary.totalCount)
        guard let seconds = viewModel.state.estimatedSecondsRemaining else {
            return Strings.Overview.analyzing(current, total)
        }
        return Strings.Overview.analyzingWithEstimate(current, total, Self.durationText(seconds))
    }

    /// Coarse on purpose: a single unit reads as an estimate, where "3 min 41 s"
    /// reads as a promise the throughput cannot keep.
    private static func durationText(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1)
        )
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

                    // Swiping is not the only way through a large library, and
                    // the alternative belongs next to the primary action rather
                    // than buried a menu deep.
                    Button(action: onOpenCategories) {
                        Label(Strings.Categories.title, systemImage: "square.stack.3d.up")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accent)
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
                    FeatureRowView(feature: feature)
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
                Button(Strings.Access.openSettings) { viewModel.send(.openSystemSettings) }
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
