//
//  TriageView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

struct TriageView: View {
    @State private var viewModel: TriageViewModel
    private let onClose: () -> Void

    init(viewModel: TriageViewModel, onClose: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onClose = onClose
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
            if viewModel.state.screenshots.isEmpty {
                chrome { EmptyScreenshotsView() }
            } else {
                deck
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

    private var deck: some View {
        VStack(spacing: Metrics.sectionSpacing) {
            header
            Spacer()
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, Metrics.screenPadding)
        .padding(.bottom, Metrics.sectionSpacing)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(Strings.Triage.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            HStack {
                CircularIconButton(systemImage: "xmark", accessibilityLabel: Strings.Triage.close, action: onClose)
                Spacer()
                CircularIconButton(systemImage: "ellipsis", accessibilityLabel: Strings.Triage.more) {}
            }
        }
        .animation(.default, value: viewModel.state.currentIndex)
    }

    // MARK: - Failure

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

    private var progressText: String {
        String(
            format: Strings.Triage.progress,
            countText(min(viewModel.state.currentIndex + 1, viewModel.state.screenshots.count)),
            countText(viewModel.state.screenshots.count)
        )
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
    static let keep = Color.blue
    static let delete = Color.red
    static let cardCornerRadius: CGFloat = 32
    static let cardStroke = Color.white.opacity(0.08)
    static let surfaceFill = Color.white.opacity(0.05)
    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
    static let decisionThreshold: CGFloat = 120
    static let actionButtonSize: CGFloat = 64
}

// MARK: - Liquid Glass

/// Same treatment as the Overview surfaces: real `glassEffect` on iOS 26,
/// translucent material + hairline border on older systems.
private struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(Metrics.surfaceFill, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Metrics.cardStroke, lineWidth: 1))
        }
    }
}

private extension View {
    func liquidGlass<S: InsettableShape>(in shape: S) -> some View {
        modifier(LiquidGlassModifier(shape: shape))
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

// MARK: - Empty state

private struct EmptyScreenshotsView: View {
    var body: some View {
        ContentUnavailableView {
            Label(Strings.Triage.emptyTitle, systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(Strings.Triage.emptyMessage)
        }
    }
}
