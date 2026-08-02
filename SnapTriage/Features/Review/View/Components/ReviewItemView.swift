//
//  ReviewItemView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 27/06/26.
//

import SwiftUI

/// One screenshot tile in the Review grid. Tapping toggles whether it's included
/// in the delete batch; excluded tiles dim so the selection reads at a glance.
struct ReviewItemView: View {
    let item: ReviewItem
    let isSelected: Bool
    let loadThumbnail: (Screenshot.ID, CGSize) async -> UIImage?
    let onToggle: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Spacing.reviewTileCornerRadius, style: .continuous)
    }

    var body: some View {
        GeometryReader { proxy in
            thumbnail
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(shape)
                .overlay { shape.strokeBorder(Palette.cardStroke, lineWidth: 1) }
                // Unselected is the resting state for a whole section, not the
                // exception, so the dim has to read as "not chosen" rather than
                // "disabled" — the checkmark carries selection.
                .opacity(isSelected ? 1 : 0.55)
                .contentShape(shape)
                // Layered above the image so the circle wins the tap, and outside
                // the dimming so the control never reads as disabled.
                .overlay(alignment: .topTrailing) { selectionToggle }
                .overlay(alignment: .bottom) { footer }
                .overlay(alignment: .topLeading) { categoryBadge }
                .onTapGesture(perform: onToggle)
                .animation(.easeInOut(duration: 0.15), value: isSelected)
                .task(id: item.id) {
                    // Request in pixels, not points, so PhotoKit downscales to the right size.
                    let target = CGSize(
                        width: proxy.size.width * displayScale,
                        height: proxy.size.height * displayScale
                    )
                    image = await loadThumbnail(item.id, target)
                }
        }
        .aspectRatio(Spacing.reviewTileAspectRatio, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.category.title)
        .accessibilityValue(sizeText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay { ProgressView() }
        }
    }

    /// The mark is 22pt for the layout, but the target is a full 44pt: this is
    /// the control that arms a deletion, so it must not be the fiddly one.
    private var selectionToggle: some View {
        Button(action: onToggle) {
            selectionMark
                .frame(width: Spacing.minimumTapTarget, height: Spacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? Strings.Review.deselect : Strings.Review.select)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var categoryBadge: some View {
        Image(systemName: item.category.systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(5)
            .background(.black.opacity(0.45), in: Circle())
            .padding(6)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text(sizeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }

    private var sizeText: String {
        MetricFormatter.size(item.byteSize)
    }
}
