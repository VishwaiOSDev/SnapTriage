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

    var body: some View {
        GeometryReader { proxy in
            thumbnail
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.thumbnailCornerRadius))
                .overlay(alignment: .bottom) { footer }
                .overlay(alignment: .topLeading) { categoryBadge }
                .overlay(alignment: .topTrailing) { selectionMark }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Spacing.thumbnailCornerRadius)
                            .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    }
                }
                .opacity(isSelected ? 1 : 0.5)
                .contentShape(Rectangle())
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
        .aspectRatio(Spacing.thumbnailAspectRatio, contentMode: .fit)
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

    private var selectionMark: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
            .font(.system(size: 20, weight: .semibold))
            .padding(6)
            .shadow(radius: 2)
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
        ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file)
    }
}
