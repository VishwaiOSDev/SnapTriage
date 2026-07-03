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

    init(viewModel: OverviewViewModel, onStartTriage: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onStartTriage = onStartTriage
    }

    var body: some View {
        ZStack {
            Metrics.background.ignoresSafeArea()
            content
        }
        .task { viewModel.send(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state.phase {
        case .idle, .loading:
            chrome { ProgressView(Strings.Triage.loading) }

        case .failed:
            chrome { failure }

        case .loaded:
            if viewModel.state.summary.totalCount == 0 {
                chrome { EmptyOverviewView() }
            } else {
                loaded
            }
        }
    }

    // Keeps the header pinned while a centered status view fills the rest.
    private func chrome<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        VStack(spacing: Metrics.sectionSpacing) {
            header
            inner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, Metrics.screenPadding)
    }

    private var loaded: some View {
        ScrollView {
            glassContainer {
                VStack(spacing: Metrics.sectionSpacing) {
                    header
                    PrivacyPillView()
                    hero
                    summaryCard
                    featureCard
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, Metrics.screenPadding)
            .padding(.bottom, Metrics.sectionSpacing)
            .animation(.default, value: viewModel.state.summary)
        }
        .scrollIndicators(.hidden)
    }

    // Lets neighboring glass elements sample and blend one another (iOS 26+).
    @ViewBuilder
    private func glassContainer<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: Metrics.sectionSpacing, content: content)
        } else {
            content()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppMarkView()
            Text(Strings.Overview.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            CircularIconButton(systemImage: "gearshape.fill", accessibilityLabel: Strings.Overview.settings) {
                viewModel.send(.openSettings)
            }
        }
    }

    private var hero: some View {
        let summary = viewModel.state.summary
        return VStack(spacing: 6) {
            VStack(spacing: 2) {
                HeroMetricText(sizeText(summary.reclaimableBytes), size: 72)
                Text(Strings.Overview.reclaimableHeadline)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .multilineTextAlignment(.center)

            Text(Strings.Overview.heroCaption(countText(summary.totalCount)))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.state.isClassifying {
                Label(
                    Strings.Overview.analyzing(
                        countText(viewModel.state.classifiedCount),
                        countText(summary.totalCount)
                    ),
                    systemImage: "wand.and.stars"
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(stats) { stat in
                        OverviewStatCard(stat: stat)
                            .frame(maxWidth: .infinity)
                    }
                }

                Button(action: onStartTriage) {
                    HStack {
                        Text(Strings.Overview.startTriage)
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .background(Metrics.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Text(Strings.Overview.startTriageHelper)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(Metrics.cardPadding)
        }
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
                value: countText(summary.usefulCount),
                title: Strings.Overview.usefulTitle,
                detail: sizeText(summary.usefulBytes),
                indicator: .icon("checkmark.circle.fill")
            ),
            TriageStat(
                id: .safeToDelete,
                value: countText(summary.safeCount),
                title: Strings.Overview.safeToDeleteTitle,
                detail: sizeText(summary.safeBytes),
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

    private func sizeText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func countText(_ value: Int) -> String {
        Self.counter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let counter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

// MARK: - Design tokens

private enum Metrics {
    static let background = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let accent = Color.blue
    static let cardCornerRadius: CGFloat = 28
    static let cardPadding: CGFloat = 20
    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    static let cardStroke = Color.white.opacity(0.08)
    static let surfaceFill = Color.white.opacity(0.05)
}

// MARK: - Liquid Glass

/// One surface treatment for every glass element. On iOS 26 it's the real
/// `glassEffect` — it samples, reflects, and refracts whatever sits behind and
/// beside it. Older systems fall back to a translucent material + hairline border.
private struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(resolvedGlass, in: shape)
        } else {
            content
                .background(Metrics.surfaceFill, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Metrics.cardStroke, lineWidth: 1))
        }
    }

    @available(iOS 26.0, *)
    private var resolvedGlass: Glass {
        if let tint {
            Glass.regular.tint(tint.opacity(0.5))
        } else {
            .regular
        }
    }
}

private extension View {
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint))
    }
}

// MARK: - Reusable surfaces

private struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Metrics.cardCornerRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct AppMarkView: View {
    var body: some View {
        Image(systemName: "doc.text.viewfinder")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Metrics.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct CircularIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 38, height: 38)
                .liquidGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Privacy pill

private struct PrivacyPillView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Metrics.accent)
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

// MARK: - Stat card

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
                .foregroundStyle(Metrics.accent)
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
                .stroke(Metrics.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Feature row

private struct FeatureRowView: View {
    let feature: FeatureHighlight
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: feature.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Metrics.accent)
                    .frame(width: 34, height: 34)
                    .background(Metrics.surfaceFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
            .padding(.horizontal, Metrics.cardPadding)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state

private struct EmptyOverviewView: View {
    var body: some View {
        ContentUnavailableView {
            Label(Strings.Triage.emptyTitle, systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(Strings.Triage.emptyMessage)
        }
    }
}

#Preview {
    let viewModel = AppComposition().makeOverview()
    viewModel.seedForPreview(.sample)
    return OverviewView(viewModel: viewModel) {}
}
