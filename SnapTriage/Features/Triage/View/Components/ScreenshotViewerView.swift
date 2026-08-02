//
//  ScreenshotViewerView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

/// Borderless look at one screenshot, for cards whose detail is too small to
/// judge from the deck. Requests a fresh thumbnail at full screen pixels, so
/// text-heavy shots stay legible; the card-sized image stands in while it loads.
struct ScreenshotViewerView: View {
    let screenshot: Screenshot
    let loadThumbnail: (Screenshot.ID, CGSize) async -> UIImage?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .task {
                    let target = CGSize(
                        width: proxy.size.width * displayScale,
                        height: proxy.size.height * displayScale
                    )
                    image = await loadThumbnail(screenshot.id, target)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // The screenshot is the content; the bar stays clear so nothing
            // competes with it, and only the close affordance floats above.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Strings.Triage.close)
                }
            }
        }
    }
}
