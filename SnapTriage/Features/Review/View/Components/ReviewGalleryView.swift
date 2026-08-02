//
//  ReviewGalleryView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 02/08/26.
//

import SwiftUI

/// Full-screen look at one screenshot, paged across the whole set behind it.
///
/// This is the screen that makes the delete button honest. Everything else in
/// Review is a 100pt thumbnail, and a screenshot is mostly text — you cannot
/// tell an expired OTP from a boarding pass at that size. So the viewer loads at
/// reading resolution and lets the user zoom, and the selection toggle travels
/// with them: decide while looking, not after.
///
/// Deletion deliberately does not live here. It stays batched behind the delete
/// bar so the user confronts the full consequence — how many, how much space —
/// and passes the system's confirmation sheet once, rather than being offered a
/// one-tap destructive shortcut on every page.
struct ReviewGalleryView: View {
    let items: [ReviewItem]
    @Binding var currentID: Screenshot.ID
    let isSelected: (Screenshot.ID) -> Bool
    let loadImage: (Screenshot.ID, CGFloat) async -> UIImage?
    let onToggle: (Screenshot.ID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(items) { item in
                    ZoomableScreenshot(
                        item: item,
                        isCurrent: item.id == currentID,
                        loadImage: loadImage
                    )
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        // Insets, not overlays. As overlays the two bars sat *on top of* the
        // screenshot and hid its first and last lines behind translucent
        // material — on a screen whose entire job is reading a screenshot.
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        // The set can shrink underneath the viewer (an undo, a library change).
        // A selection that no longer exists leaves TabView showing nothing.
        .onChange(of: items) { _, current in
            if !current.contains(where: { $0.id == currentID }) { dismiss() }
        }
    }

    private var currentItem: ReviewItem? {
        items.first { $0.id == currentID }
    }

    private var currentIndex: Int? {
        items.firstIndex { $0.id == currentID }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Button(Strings.Review.viewerDone) { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 12)

            if let currentIndex {
                Text(
                    Strings.Review.viewerPosition(
                        MetricFormatter.count(currentIndex + 1),
                        MetricFormatter.count(items.count)
                    )
                )
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let item = currentItem {
            let selected = isSelected(item.id)
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: item.category.systemImage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.category.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text(metadata(for: item))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // The button states what will happen, not what is true: armed, it
                // offers the way out; at rest, it offers the arm. Colour carries
                // the state so the label never has to describe it.
                Button {
                    onToggle(item.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .semibold))
                        Text(selected ? Strings.Review.viewerKeepThis : Strings.Review.viewerSelectThis)
                            .font(.headline)
                    }
                    .foregroundStyle(selected ? Palette.delete : .white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Spacing.minimumTapTarget + 8)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                        shape
                            .fill(selected ? Palette.delete.opacity(0.16) : Palette.surfaceFill)
                            .overlay {
                                shape.strokeBorder(
                                    selected ? Palette.delete.opacity(0.7) : Palette.cardStroke,
                                    lineWidth: 1
                                )
                            }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
            .animation(.easeInOut(duration: 0.15), value: selected)
        }
    }

    private func metadata(for item: ReviewItem) -> String {
        [item.creationDate.map(MetricFormatter.timestamp), MetricFormatter.size(item.byteSize)]
            .compactMap(\.self)
            .joined(separator: " · ")
    }
}

// MARK: - Page

/// One page: the screenshot at reading resolution, pinch- and double-tap-zoomable.
private struct ZoomableScreenshot: View {
    let item: ReviewItem
    /// Whether this page is the one on screen. TabView keeps neighbouring pages
    /// alive, so without this a page you zoomed stays zoomed and half off-centre
    /// when you come back to it.
    let isCurrent: Bool
    let loadImage: (Screenshot.ID, CGFloat) async -> UIImage?

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let maximumScale: CGFloat = 6
    private let doubleTapScale: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnification(in: proxy.size))
                // Only intercept drags once zoomed in; at rest the drag has to
                // reach TabView so the user can still page between screenshots.
                .gesture(pan(in: proxy.size), isEnabled: scale > 1)
                .onTapGesture(count: 2) { toggleZoom() }
                .onChange(of: isCurrent) { _, current in
                    if !current { resetZoom() }
                }
                .task(id: item.id) {
                    resetZoom()
                    let longEdge = max(proxy.size.width, proxy.size.height) * displayScale
                    // Headroom so a zoomed screenshot stays legible rather than
                    // resolving into the pixels of a screen-sized rendition.
                    image = await loadImage(item.id, min(longEdge * 2, 3000))
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func magnification(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(committedScale * value.magnification, 1), maximumScale)
                // Zooming back out has to reel the image in too, or it stays
                // parked wherever the last pan left it.
                offset = clamped(committedOffset, in: size)
            }
            .onEnded { _ in
                committedScale = scale
                if scale == 1 { resetPan() } else { committedOffset = offset }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(
                    CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    ),
                    in: size
                )
            }
            .onEnded { _ in committedOffset = offset }
    }

    /// Keeps the zoomed image covering the frame. Unclamped, a drag could throw
    /// the screenshot clean off screen and leave the page looking broken.
    private func clamped(_ offset: CGSize, in size: CGSize) -> CGSize {
        let limit = CGSize(
            width: max((size.width * scale - size.width) / 2, 0),
            height: max((size.height * scale - size.height) / 2, 0)
        )
        return CGSize(
            width: min(max(offset.width, -limit.width), limit.width),
            height: min(max(offset.height, -limit.height), limit.height)
        )
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if scale > 1 {
                resetZoom()
            } else {
                scale = doubleTapScale
                committedScale = doubleTapScale
            }
        }
    }

    private func resetZoom() {
        scale = 1
        committedScale = 1
        resetPan()
    }

    private func resetPan() {
        offset = .zero
        committedOffset = .zero
    }
}
