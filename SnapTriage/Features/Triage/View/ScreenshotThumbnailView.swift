//
//  ScreenshotThumbnailView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

struct ScreenshotThumbnailView: View {
    let screenshot: Screenshot
    let loadThumbnail: (Screenshot.ID, CGSize) async -> UIImage?
    let onSelect: () -> Void
    
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    
    var body: some View {
        GeometryReader { proxy in
            thumbnail
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.thumbnailCornerRadius))
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
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
}
