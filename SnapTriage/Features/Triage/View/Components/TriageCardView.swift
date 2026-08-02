//
//  TriageCardView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

/// One screenshot in the deck: the image, a metadata footer, and the current
/// classification. Loads its own thumbnail sized for the presentation mode.
struct TriageCardView: View {
    let screenshot: Screenshot
    /// `nil` while the pipeline is still classifying this card.
    let classification: ScreenshotClassification?
    let imageMode: CardImageMode
    let loadThumbnail: (Screenshot.ID, CGSize) async -> UIImage?
    var onTap: () -> Void = {}

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TriageMetrics.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // A dedicated footer keeps Fit genuinely unobscured; metadata
                // no longer covers the bottom of the screenshot.
                metadataBar
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Backs the letterbox bars in Fit mode.
            .background(Color.black)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.cardStroke, lineWidth: 1))
            // Hit-testing is confined to the card itself; the surrounding deck
            // padding must stay inert so it can't swallow header/close taps.
            .contentShape(shape)
            // Touch tap-to-zoom is handled by the deck's drag recognizer — a tap
            // gesture here would outrank it and delay every swipe. VoiceOver has
            // no drag to read, so it gets the action declared directly.
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onTap)
            // Flatten before the shadow so the blur sees one layer, not the
            // whole subtree, per frame while the card drags and rotates.
            .compositingGroup()
            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
            .task(id: screenshot.id) {
                // Request the complete source at enough resolution for the
                // cropped Fill presentation as well as the smaller Fit one.
                let target = thumbnailTargetSize(
                    filling: proxy.size,
                    displayScale: displayScale
                )
                image = await loadThumbnail(screenshot.id, target)
            }
        }
        .aspectRatio(Spacing.thumbnailAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            GeometryReader { proxy in
                // One layer that switches content mode, not one layer per mode.
                // The hidden copy still cost a full texture, and the card is
                // recomposited on every frame of a drag or a fly-off. Toggling
                // now reads as a zoom between the two framings rather than a
                // cross-fade, which suits Fit ↔ Fill anyway.
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: imageMode == .fill ? .fill : .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .animation(
                .easeInOut(duration: TriageMetrics.imageModeTransitionDuration),
                value: imageMode
            )
        } else {
            placeholder
        }
    }

    private func thumbnailTargetSize(
        filling viewport: CGSize,
        displayScale: CGFloat
    ) -> CGSize {
        let source = CGSize(
            width: CGFloat(screenshot.pixelWidth),
            height: CGFloat(screenshot.pixelHeight)
        )
        let viewportPixels = CGSize(
            width: viewport.width * displayScale,
            height: viewport.height * displayScale
        )
        guard source.width > 0, source.height > 0 else { return viewportPixels }

        // Match the source aspect ratio and size it for aspect-fill. PhotoKit
        // can then return an uncropped image with no quality loss when toggled.
        let scale = min(
            max(viewportPixels.width / source.width, viewportPixels.height / source.height),
            1
        )
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    // Polished stand-in while PhotoKit loads (or in previews with no library).
    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.15, blue: 0.22), Color(red: 0.06, green: 0.07, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: classification?.category.systemImage ?? "hourglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    private var metadataBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(classification?.category.title ?? Strings.Triage.analyzing)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            dispositionBadge
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.35))
    }

    // Pending → neutral "Analyzing…"; otherwise the three retention states, so a
    // needs-review card never reads as "safe to delete".
    private var dispositionBadge: some View {
        let (text, color): (String, Color) = switch classification?.disposition {
        case .safeToDelete?: (Strings.Triage.safeToDelete, Palette.delete)
        case .useful?:       (Strings.Triage.worthKeeping, Palette.keep)
        case .needsReview?:  (Strings.Triage.needsReview, Palette.review)
        case nil:            (Strings.Triage.analyzing, Palette.neutral)
        }
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(color.opacity(0.15), in: Capsule())
    }

    // "Today, 9:41 AM • 1.8 MB"
    private var metadataText: String {
        [dateText, MetricFormatter.size(screenshot.byteSize)]
            .compactMap(\.self)
            .joined(separator: " • ")
    }

    private var dateText: String? {
        guard let date = screenshot.creationDate else { return nil }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) {
            return Strings.Triage.today(time)
        }
        if Calendar.current.isDateInYesterday(date) {
            return Strings.Triage.yesterday(time)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
