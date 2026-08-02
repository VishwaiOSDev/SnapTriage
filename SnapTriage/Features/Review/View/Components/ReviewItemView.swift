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
                .overlay(alignment: .bottom) { timestamp }
                .overlay { shape.strokeBorder(Palette.cardStroke, lineWidth: 1) }
                // Unselected is the resting state for a whole section, not the
                // exception, so the dim has to read as "not chosen" rather than
                // "disabled" — the checkmark carries selection.
                .opacity(isSelected ? 1 : 0.55)
                .contentShape(shape)
                // Layered above the image so the circle wins the tap, and outside
                // the dimming so the control never reads as disabled.
                .overlay(alignment: .topTrailing) { selectionToggle }
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

    private var selectionMark: some View {
        Group {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Palette.delete, in: Circle())
            } else {
                Circle()
                    .fill(.black.opacity(0.3))
                    .overlay { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5) }
                    .frame(width: 22, height: 22)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(7)
    }

    @ViewBuilder
    private var timestamp: some View {
        if let text = timestampText {
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.bottom, 8)
                .padding(.horizontal, 6)
        }
    }

    private var timestampText: String? {
        item.creationDate.map(MetricFormatter.timestamp)
    }

    // The tile shows the date, not the size it replaced, so VoiceOver carries both.
    private var accessibilityValue: String {
        [timestampText, MetricFormatter.size(item.byteSize)]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}
