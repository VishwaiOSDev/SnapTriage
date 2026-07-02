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

// MARK: - Card

private struct TriageCardView: View {
    let screenshot: Screenshot
    let category: ScreenshotCategory
    let loadThumbnail: (Screenshot.ID, CGSize) async -> UIImage?

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        GeometryReader { proxy in
            preview
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay(alignment: .bottom) { metadataBar }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Metrics.cardStroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                .task(id: screenshot.id) {
                    // Request in pixels, not points, so PhotoKit downscales to the right size.
                    let target = CGSize(
                        width: proxy.size.width * displayScale,
                        height: proxy.size.height * displayScale
                    )
                    image = await loadThumbnail(screenshot.id, target)
                }
        }
        .aspectRatio(Spacing.thumbnailAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    // Polished stand-in while PhotoKit loads (or in previews with no library).
    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.15, blue: 0.22), Color(red: 0.06, green: 0.07, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: category.systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    private var metadataBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            dispositionBadge
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.35))
    }

    private var dispositionBadge: some View {
        let safe = category.disposition == .safeToDelete
        return Text(safe ? Strings.Triage.safeToDelete : Strings.Triage.worthKeeping)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(safe ? Metrics.delete : Metrics.keep)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background((safe ? Metrics.delete : Metrics.keep).opacity(0.15), in: Capsule())
    }

    // "Today, 9:41 AM • 1.8 MB"
    private var metadataText: String {
        [dateText, sizeText].compactMap(\.self).joined(separator: " • ")
    }

    private var dateText: String? {
        guard let date = screenshot.creationDate else { return nil }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) {
            return String(format: Strings.Triage.today, time)
        }
        if Calendar.current.isDateInYesterday(date) {
            return String(format: Strings.Triage.yesterday, time)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(screenshot.byteSize), countStyle: .file)
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
