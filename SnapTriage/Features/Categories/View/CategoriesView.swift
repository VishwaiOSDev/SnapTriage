//
//  CategoriesView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import SwiftUI

/// Bulk triage. The classifier has already read every screenshot; this screen
/// spends that work instead of asking the user to re-derive it one swipe at a
/// time. Clearing the three largest buckets here is the difference between a
/// forty-minute chore and a two-minute one — and whatever is genuinely ambiguous
/// is still there afterwards, waiting in the deck.
struct CategoriesView: View {
    @State private var viewModel: CategoriesViewModel
    private let onOpenCategory: (ScreenshotCategory) -> Void

    init(viewModel: CategoriesViewModel, onOpenCategory: @escaping (ScreenshotCategory) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onOpenCategory = onOpenCategory
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            content
        }
        .navigationTitle(Strings.Categories.title)
        .navigationBarTitleDisplayMode(.inline)
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
            if viewModel.state.breakdown.isEmpty {
                chrome { EmptyCategoriesView() }
            } else {
                loaded
            }
        }
    }

    private func chrome<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        inner()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Spacing.screenPadding)
    }

    private var loaded: some View {
        ScrollView {
            VStack(spacing: 12) {
                intro
                GlassCard {
                    VStack(spacing: 0) {
                        let groups = viewModel.state.groups
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            CategoryRow(group: group) { onOpenCategory(group.category) }
                            if index < groups.count - 1 {
                                Divider()
                                    .overlay(Color.white.opacity(0.06))
                                    .padding(.leading, 64)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                footnote
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.vertical, Spacing.sectionSpacing)
        }
        .scrollIndicators(.hidden)
        .animation(.default, value: viewModel.state.breakdown)
    }

    private var intro: some View {
        VStack(spacing: 4) {
            Text(Strings.Categories.headline(countText(viewModel.state.breakdown.undecidedCount)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(Strings.Categories.subheadline)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var footnote: some View {
        VStack(spacing: 6) {
            if viewModel.state.breakdown.unclassifiedCount > 0 {
                Label(
                    Strings.Categories.stillAnalyzing(
                        countText(viewModel.state.breakdown.unclassifiedCount)
                    ),
                    systemImage: "wand.and.stars"
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Text(Strings.Categories.safetyNote)
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private var failure: some View {
        ContentUnavailableView {
            Label(Strings.Access.title, systemImage: "lock.fill")
        } description: {
            Text(viewModel.state.errorMessage ?? Strings.Error.generic)
        } actions: {
            Button(Strings.Access.retry) { viewModel.send(.retry) }
        }
    }

    // MARK: - Display

    private func countText(_ value: Int) -> String {
        MetricFormatter.count(value)
    }
}

// MARK: - Row

private struct CategoryRow: View {
    let group: CategoryGroup
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: group.category.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(Palette.surfaceFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.category.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.cardPadding)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.category.title)
        .accessibilityValue(detail)
    }

    private var detail: String {
        Strings.Categories.rowDetail(
            MetricFormatter.count(group.count),
            MetricFormatter.size(group.byteSize)
        )
    }

    private var tint: Color {
        switch group.disposition {
        case .safeToDelete: Palette.delete
        case .useful:       Palette.accent
        case .needsReview:  .orange
        }
    }
}

// MARK: - Empty state

private struct EmptyCategoriesView: View {
    var body: some View {
        ContentUnavailableView {
            Label(Strings.Categories.emptyTitle, systemImage: "checkmark.circle")
        } description: {
            Text(Strings.Categories.emptyMessage)
        }
    }
}

#if DEBUG
@MainActor
private struct CategoriesView_Previews: PreviewProvider {
    static var previews: some View {
        makePreview()
    }

    private static func makePreview() -> some View {
        let viewModel = AppComposition().makeCategories()
        viewModel.seedForPreview(
            CategoryBreakdown(
                groups: [
                    CategoryGroup(
                        category: .otp,
                        disposition: .useful,
                        ids: (0..<312).map { "otp-\($0)" },
                        byteSize: 480_000_000
                    ),
                    CategoryGroup(
                        category: .social,
                        disposition: .safeToDelete,
                        ids: (0..<184).map { "social-\($0)" },
                        byteSize: 1_100_000_000
                    ),
                    CategoryGroup(
                        category: .shopping,
                        disposition: .needsReview,
                        ids: (0..<27).map { "shop-\($0)" },
                        byteSize: 96_000_000
                    )
                ],
                unclassifiedCount: 41,
                decidedCount: 88
            )
        )
        return CategoriesView(viewModel: viewModel, onOpenCategory: { _ in })
            .preferredColorScheme(.dark)
    }
}
#endif
