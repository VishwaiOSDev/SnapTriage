//
//  ReviewView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import SwiftUI

struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ReviewViewModel

    init(viewModel: ReviewViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private let columns = [
        GridItem(.adaptive(minimum: Spacing.thumbnailMinWidth), spacing: Spacing.gridSpacing)
    ]

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
            if viewModel.state.items.isEmpty {
                chrome { EmptyReviewView() }
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
        VStack(spacing: Metrics.sectionSpacing) {
            header
            ScrollView {
                VStack(spacing: Metrics.sectionSpacing) {
                    hero
                    grid
                }
                .padding(.bottom, Metrics.sectionSpacing)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, Metrics.screenPadding)
        .safeAreaInset(edge: .bottom) { deleteBar }
        .animation(.default, value: viewModel.state.items)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.Access.back)
            Text(Strings.Review.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
        }
    }

    private var hero: some View {
        VStack(spacing: 4) {
            HeroMetricText(sizeText(viewModel.state.reclaimableBytes), size: 64)
            Text(Strings.Review.reclaimableHeadline)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(selectionCaption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .animation(.default, value: viewModel.state.selectedIDs)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: Spacing.gridSpacing) {
            ForEach(viewModel.state.items) { item in
                ReviewItemView(
                    item: item,
                    isSelected: viewModel.state.selectedIDs.contains(item.id),
                    loadThumbnail: { id, size in
                        await viewModel.thumbnail(for: id, targetSize: size)
                    },
                    onToggle: { viewModel.send(.toggle(item.id)) }
                )
            }
        }
    }

    private var deleteBar: some View {
        Button {
            viewModel.send(.deleteSelected)
        } label: {
            HStack(spacing: 8) {
                if viewModel.state.isDeleting {
                    ProgressView()
                        .tint(.white)
                    Text(Strings.Review.deleting)
                } else {
                    Image(systemName: "trash.fill")
                    Text(deleteTitle)
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Metrics.destructive, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(viewModel.state.hasSelection ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.state.hasSelection || viewModel.state.isDeleting)
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
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

    private var deleteTitle: String {
        Strings.Review.deleteButton(
            countText(viewModel.state.selectedCount),
            sizeText(viewModel.state.reclaimableBytes)
        )
    }

    private var selectionCaption: String {
        Strings.Review.selectionCaption(
            countText(viewModel.state.selectedCount),
            countText(viewModel.state.items.count)
        )
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
    static let destructive = Color.red
    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
}

// MARK: - Empty state

private struct EmptyReviewView: View {
    var body: some View {
        ContentUnavailableView {
            Label(Strings.Review.emptyTitle, systemImage: "checkmark.circle")
        } description: {
            Text(Strings.Review.emptyMessage)
        }
    }
}

#if DEBUG
@MainActor
private struct ReviewView_Previews: PreviewProvider {
    static var previews: some View {
        makePreview()
    }

    private static func makePreview() -> some View {
        let viewModel = AppComposition().makeReview()
        viewModel.seedForPreview([
            ReviewItem(id: "1", category: .social, byteSize: 2_400_000),
            ReviewItem(id: "2", category: .article, byteSize: 1_800_000),
            ReviewItem(id: "3", category: .conversation, byteSize: 3_100_000),
            ReviewItem(id: "4", category: .photo, byteSize: 5_600_000)
        ])
        return ReviewView(viewModel: viewModel)
    }
}
#endif
