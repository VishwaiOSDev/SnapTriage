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
        .navigationTitle(viewModel.scope.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
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
                DeletionSummaryCard(
                    selectedCount: viewModel.state.selectedCount,
                    reclaimableBytes: viewModel.state.reclaimableBytes
                )
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(viewModel.scope.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    if viewModel.state.isRefreshing {
                        ProgressView().controlSize(.mini)
                    }
                    Text(navSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if hasContent {
                Button {
                    viewModel.send(.toggleSelectAll)
                } label: {
                    Text(
                        viewModel.state.areAllSelected
                            ? Strings.Review.deselectAll
                            : Strings.Review.selectAll
                    )
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            // The bulk keep lives here rather than on the category list: it is
            // safe, but it still retires the whole bucket, and the user should
            // be able to see what they are dismissing while they do it.
            if hasContent && viewModel.scope.isCategory {
                Menu {
                    Button {
                        viewModel.send(.keepAll)
                    } label: {
                        Label(
                            Strings.Review.keepAll(MetricFormatter.count(viewModel.state.items.count)),
                            systemImage: "checkmark.circle"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var hasContent: Bool {
        viewModel.state.phase == .loaded && !viewModel.state.items.isEmpty
    }

    private var navSubtitle: String {
        let selected = MetricFormatter.count(viewModel.state.selectedCount)
        guard viewModel.scope.isCategory else { return Strings.Review.navSubtitle(selected) }
        return Strings.Review.scopedNavSubtitle(
            selected,
            MetricFormatter.count(viewModel.state.items.count)
        )
    }

    // MARK: - Sections

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
                    subtitle: Strings.Review.markedSectionSubtitle(MetricFormatter.count(items.count)),
                    trailing: Strings.Review.itemCount(MetricFormatter.count(items.count))
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
                    title: suggestedTitle,
                    subtitle: suggestedSubtitle(count: items.count)
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

    // In the triage inbox this section is the classifier's proposal. In a
    // category scope it is simply the rest of the bucket, and calling that a
    // suggestion would put words in the classifier's mouth.
    private var suggestedTitle: String {
        viewModel.scope.isCategory
            ? Strings.Review.scopedSectionTitle
            : Strings.Review.suggestedSectionTitle
    }

    private func suggestedSubtitle(count: Int) -> String {
        let count = MetricFormatter.count(count)
        let size = MetricFormatter.size(viewModel.state.suggestedBytes)
        return viewModel.scope.isCategory
            ? Strings.Review.scopedSectionSubtitle(count, size)
            : Strings.Review.suggestedSectionSubtitle(count, size)
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

    // MARK: - Delete bar

    private var deleteBar: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.send(.deleteSelected)
            } label: {
                HStack(spacing: 14) {
                    if viewModel.state.isDeleting {
                        ProgressView()
                            .tint(.white)
                        Text(Strings.Review.deleting)
                            .font(.headline)
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 20, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deleteTitle)
                                .font(.headline)
                            Text(Strings.Review.deleteSubtitle(
                                MetricFormatter.size(viewModel.state.reclaimableBytes)
                            ))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: viewModel.state.isDeleting ? .center : .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(minHeight: 56)
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(
                GlossyActionButtonStyle(
                    tone: .destructive,
                    shape: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            )
            .opacity(viewModel.state.hasSelection ? 1 : 0.4)
            .disabled(!viewModel.state.hasSelection || viewModel.state.isDeleting)
            .animation(.default, value: viewModel.state.selectedIDs)

            Label(Strings.Review.deleteFooter, systemImage: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
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
        Strings.Review.deleteButton(MetricFormatter.count(viewModel.state.selectedCount))
    }
}


// MARK: - Deletion summary

/// The one card that states the consequence in full before the user commits:
/// how many, how much space, and that the deletion is recoverable for 30 days.
private struct DeletionSummaryCard: View {
    let selectedCount: Int
    let reclaimableBytes: Int

    var body: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.delete)
                        .frame(width: 52, height: 52)
                        .background(Palette.delete.opacity(0.15), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Strings.Review.summaryLead)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(headline)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(hasSelection ? Palette.delete : .white)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Divider().overlay(Palette.cardStroke)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(Strings.Review.recoveryNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.cardPadding)
        }
        .animation(.default, value: selectedCount)
    }

    private var hasSelection: Bool { selectedCount > 0 }

    private var headline: String {
        hasSelection
            ? Strings.Review.summaryCount(MetricFormatter.count(selectedCount))
            : Strings.Review.summaryEmptyTitle
    }

    private var detail: String {
        hasSelection
            ? Strings.Review.summaryFreeUp(MetricFormatter.size(reclaimableBytes))
            : Strings.Review.summaryEmptyDetail
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
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
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

private extension SectionHeader where Accessory == Text {
    /// Header whose accessory is a plain item count, e.g. "1,059 ITEMS".
    init(title: String, subtitle: String, trailing: String) {
        self.init(title: title, subtitle: subtitle) {
            Text(trailing.localizedUppercase)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
