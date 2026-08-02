//
//  ReviewView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import SwiftUI

struct ReviewView: View {
    @State private var viewModel: ReviewViewModel

    init(viewModel: ReviewViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private let columns = [
        GridItem(.adaptive(minimum: Spacing.thumbnailMinWidth), spacing: Spacing.gridSpacing)
    ]

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle(Strings.Review.title)
        .navigationBarTitleDisplayMode(.inline)
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
            if viewModel.state.items.isEmpty {
                status { EmptyReviewView(scope: viewModel.scope) }
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
                hero
                markedSection
                suggestedSection
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.sectionSpacing)
            .padding(.bottom, Spacing.sectionSpacing)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { deleteBar }
        .animation(.default, value: viewModel.state.items)
    }

    private var hero: some View {
        VStack(spacing: 4) {
            HeroMetricText(MetricFormatter.size(viewModel.state.reclaimableBytes), size: 64)
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

    // The two sections carry different weight, and the layout has to say so.
    // What the user swiped left is theirs and arrives armed; what the classifier
    // merely guessed is presented as a proposal they can accept in one tap.
    @ViewBuilder
    private var markedSection: some View {
        let items = viewModel.state.markedItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: Strings.Review.markedSectionTitle,
                    subtitle: Strings.Review.markedSectionSubtitle(MetricFormatter.count(items.count))
                )
                grid(items)
            }
        }
    }

    @ViewBuilder
    private var suggestedSection: some View {
        let items = viewModel.state.suggestedItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: Strings.Review.suggestedSectionTitle,
                    subtitle: Strings.Review.suggestedSectionSubtitle(
                        MetricFormatter.count(items.count),
                        MetricFormatter.size(viewModel.state.suggestedBytes)
                    )
                ) {
                    Button {
                        viewModel.send(.toggleAllSuggestions)
                    } label: {
                        Text(
                            viewModel.state.areAllSuggestionsSelected
                                ? Strings.Review.deselectAll
                                : Strings.Review.selectAll
                        )
                        .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accent)
                }
                grid(items)
            }
        }
    }

    private func grid(_ items: [ReviewItem]) -> some View {
        LazyVGrid(columns: columns, spacing: Spacing.gridSpacing) {
            ForEach(items) { item in
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
            .background(Palette.delete, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(viewModel.state.hasSelection ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.state.hasSelection || viewModel.state.isDeleting)
        .padding(.horizontal, Spacing.screenPadding)
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

    private var deleteTitle: String {
        Strings.Review.deleteButton(
            MetricFormatter.count(viewModel.state.selectedCount),
            MetricFormatter.size(viewModel.state.reclaimableBytes)
        )
    }

    private var selectionCaption: String {
        Strings.Review.selectionCaption(
            MetricFormatter.count(viewModel.state.selectedCount),
            MetricFormatter.count(viewModel.state.items.count)
        )
    }
}

// MARK: - Section header

private struct SectionHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory

    init(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            accessory
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
            ReviewItem(id: "1", category: .social, byteSize: 2_400_000, source: .userMarked),
            ReviewItem(id: "2", category: .article, byteSize: 1_800_000, source: .userMarked),
            ReviewItem(id: "3", category: .conversation, byteSize: 3_100_000, source: .suggested),
            ReviewItem(id: "4", category: .photo, byteSize: 5_600_000, source: .suggested)
        ])
        return NavigationStack {
            ReviewView(viewModel: viewModel)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
