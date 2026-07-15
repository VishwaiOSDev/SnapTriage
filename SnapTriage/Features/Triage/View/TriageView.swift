//
//  TriageView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

private enum CardImageMode: String {
    case fit
    case fill

    var toggled: Self { self == .fit ? .fill : .fit }
}

struct TriageView: View {
    @State private var viewModel: TriageViewModel
    private let onClose: () -> Void

    /// Drag state is pure UI: it lives in the view and never reaches the
    /// ViewModel. Only the final decision crosses the boundary via `send`.
    @State private var drag: CGSize = .zero
    @State private var isDismissing = false
    @State private var isUndoing = false
    @State private var fullScreenShot: Screenshot?

    /// A presentation preference, not domain state. Fit is the safer default:
    /// the user sees the whole screenshot unless they explicitly choose crop.
    @AppStorage("triage.imageDisplayMode") private var imageMode: CardImageMode = .fill
    @State private var showStartOverConfirmation = false

    /// Shared and prepared ahead of the first swipe: creating a generator and
    /// firing it cold spins up the haptic engine, which stalls the first fly-off.
    @State private var haptic = UIImpactFeedbackGenerator(style: .medium)
    @State private var undoHaptic = UIImpactFeedbackGenerator(style: .soft)

    init(viewModel: TriageViewModel, onClose: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: viewModel)
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Metrics.background.ignoresSafeArea()
            content
        }
        .task {
            viewModel.send(.onAppear)
            haptic.prepare()
            undoHaptic.prepare()
        }
        .fullScreenCover(item: $fullScreenShot) { screenshot in
            ScreenshotViewerView(screenshot: screenshot) { id, size in
                await viewModel.thumbnail(for: id, targetSize: size)
            }
        }
        .sensoryFeedback(.selection, trigger: imageMode)
        .alert(
            Strings.Triage.startOverConfirmTitle,
            isPresented: $showStartOverConfirmation
        ) {
            Button(Strings.Triage.cancel, role: .cancel) {}
            Button(Strings.Triage.startOver, role: .destructive) {
                viewModel.send(.startOver)
            }
        } message: {
            Text(Strings.Triage.startOverConfirmMessage)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state.phase {
        case .idle, .loading:
            chrome { ProgressView(Strings.Triage.loading) }

        case .failed:
            chrome { failure }

        case .loaded:
            if viewModel.state.screenshots.isEmpty {
                chrome { EmptyScreenshotsView() }
            } else if viewModel.state.isFinished {
                chrome { finished }
            } else {
                deck
            }
        }
    }

    // Keeps the header pinned while a centered status view fills the rest.
    private func chrome<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        VStack(spacing: Metrics.sectionSpacing) {
            header
            inner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, Metrics.screenPadding)
    }

    private var deck: some View {
        VStack(spacing: Metrics.sectionSpacing) {
            header
            categoryPill
            cardStack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            swipeHints
            actionButtons
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, Metrics.screenPadding)
        .padding(.bottom, Metrics.sectionSpacing)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(Strings.Triage.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            HStack {
                CircularIconButton(systemImage: "xmark", accessibilityLabel: Strings.Triage.close, action: onClose)
                Spacer()
                overflowMenu
            }
        }
        .animation(.default, value: viewModel.state.currentIndex)
    }

    // MARK: - Overflow menu

    private var overflowMenu: some View {
        Menu {
            Button {
                withAnimation(.easeInOut(duration: Metrics.imageModeTransitionDuration)) {
                    imageMode = imageMode.toggled
                }
            } label: {
                Label(
                    imageMode == .fill
                        ? Strings.Triage.fitImage
                        : Strings.Triage.fillImage,
                    systemImage: imageMode == .fill
                        ? "arrow.down.forward.and.arrow.up.backward"
                        : "arrow.up.left.and.arrow.down.right"
                )
            }

            // Only offer a mid-pass restart while there is progress to discard;
            // the finished screen already exposes its own restart control.
            if viewModel.state.hasProgress && !viewModel.state.isFinished {
                Divider()
                // This only opens a confirmation; reserve destructive red for
                // the action that actually clears the pass.
                Button {
                    requestStartOver()
                } label: {
                    Label(Strings.Triage.restartTriage, systemImage: "arrow.counterclockwise")
                }
            }

            #if DEBUG
            Divider()
            // Wipes the classification cache and re-runs the pipeline. Debug-only:
            // for exercising categorization (and the background pass) end to end.
            Button {
                viewModel.send(.recategorizeAll)
            } label: {
                Label("Re-categorize all (debug)", systemImage: "wand.and.stars")
            }
            #endif
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 38, height: 38)
                .liquidGlass(in: Circle())
                .padding(3)
                .contentShape(Circle())
        }
        .accessibilityLabel(Strings.Triage.more)
    }

    // MARK: - Category pill

    @ViewBuilder
    private var categoryPill: some View {
        if let current = viewModel.state.current {
            // Pending classification shows a neutral "Analyzing…" pill — never a
            // premature category or safe-to-delete verdict.
            let classification = viewModel.state.classification(for: current)
            HStack(spacing: 6) {
                Image(systemName: classification?.category.systemImage ?? "hourglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Metrics.keep)
                Text(classification?.category.title ?? Strings.Triage.analyzing)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .liquidGlass(in: Capsule())
            .animation(.default, value: classification)
        }
    }

    // MARK: - Card stack

    // A ForEach keyed by screenshot id keeps view identity stable while a card
    // moves from the back slot to the front, so its already-loaded thumbnail
    // survives the promotion instead of flashing back to the placeholder.
    private var cardStack: some View {
        ZStack {
            ForEach(deckWindow) { screenshot in
                deckCard(for: screenshot, isTop: screenshot.id == viewModel.state.current?.id)
            }
        }
    }

    private func deckCard(for screenshot: Screenshot, isTop: Bool) -> some View {
        let scale: CGFloat = isTop
            ? 1 - min(abs(drag.width) / 2400, 0.04)
            : 0.92 + 0.08 * dragProgress
        let rotation: Double = isTop ? Double(drag.width / 18) : 0
        return card(for: screenshot)
            .overlay { if isTop && !isUndoing { decisionStamps } }
            .scaleEffect(scale)
            .opacity(isTop ? 1 : 0.6 + 0.4 * Double(dragProgress))
            .offset(isTop ? drag : .zero)
            .rotationEffect(.degrees(rotation), anchor: .bottom)
            .onTapGesture { if isTop { fullScreenShot = screenshot } }
            .gesture(isTop ? dragGesture : nil)
    }

    // Back-to-front render order: up-next behind, current on top.
    private var deckWindow: [Screenshot] {
        [viewModel.state.upNext, viewModel.state.current].compactMap(\.self)
    }

    private func card(for screenshot: Screenshot) -> some View {
        TriageCardView(
            screenshot: screenshot,
            classification: viewModel.state.classification(for: screenshot),
            imageMode: imageMode,
            loadThumbnail: { id, size in
                await viewModel.thumbnail(for: id, targetSize: size)
            }
        )
    }

    // Tinder-style corner stamps that fade in as the card travels.
    private var decisionStamps: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
                .fill(stampColor.opacity(0.25 * Double(dragProgress)))
            HStack {
                DecisionStamp(text: Strings.Triage.keepBadge, color: Metrics.keep, angle: -12)
                    .opacity(drag.width > 0 ? Double(dragProgress) : 0)
                Spacer()
                DecisionStamp(text: Strings.Triage.deleteBadge, color: Metrics.delete, angle: 12)
                    .opacity(drag.width < 0 ? Double(dragProgress) : 0)
            }
            .padding(24)
        }
        .allowsHitTesting(false)
    }

    private var stampColor: Color {
        drag.width >= 0 ? Metrics.keep : Metrics.delete
    }

    private var dragProgress: CGFloat {
        min(max((abs(drag.width) - 16) / (Metrics.decisionThreshold - 16), 0), 1)
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isDismissing else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !isDismissing else { return }
                if value.translation.width > Metrics.decisionThreshold {
                    fly(.keep)
                } else if value.translation.width < -Metrics.decisionThreshold {
                    fly(.markForDeletion)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        drag = .zero
                    }
                }
            }
    }

    private func fly(_ decision: TriageDecision) {
        guard !isDismissing, viewModel.state.current != nil else { return }
        isDismissing = true
        haptic.impactOccurred()
        haptic.prepare()

        let direction: CGFloat = decision == .keep ? 1 : -1
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            drag = CGSize(width: direction * 640, height: drag.height + 40)
        }
        // Let the fly-off play, then advance the deck and reset without animating
        // back, so the next card appears centered instead of sliding in.
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            viewModel.send(.decide(decision))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { drag = .zero }
            isDismissing = false
        }
    }

    /// Reintroduces the last card from the same edge it left. Mutating the deck
    /// and positioning the card happen without animation; the next run-loop
    /// animates only the return to center, avoiding a flash at the origin.
    private func undo() {
        guard !isDismissing, let decision = viewModel.state.lastDecision else { return }
        isDismissing = true
        isUndoing = true
        undoHaptic.impactOccurred()
        undoHaptic.prepare()

        let direction: CGFloat = decision == .keep ? 1 : -1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            viewModel.send(.undo)
            drag = CGSize(width: direction * 640, height: 40)
        }

        Task { @MainActor in
            await Task.yield()
            withAnimation(.spring(response: 0.48, dampingFraction: 0.82)) {
                drag = .zero
            }
            try? await Task.sleep(for: .milliseconds(480))
            isUndoing = false
            isDismissing = false
        }
    }

    // MARK: - Hints & actions

    private var swipeHints: some View {
        HStack(spacing: 0) {
            hintLabel(
                text: Strings.Triage.swipeRightHint,
                arrow: "arrow.right",
                color: Metrics.controlKeep,
                arrowLeading: true
            )
            Spacer(minLength: Metrics.hintGroupSpacing)
            hintDivider
            Spacer(minLength: Metrics.hintGroupSpacing)
            hintLabel(
                text: Strings.Triage.swipeLeftHint,
                arrow: "arrow.left",
                color: Metrics.controlDelete,
                arrowLeading: false
            )
        }
    }

    private func hintLabel(text: String, arrow: String, color: Color, arrowLeading: Bool) -> some View {
        HStack(spacing: Metrics.hintArrowSpacing) {
            if arrowLeading { glossyArrow(arrow, color: color) }
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.72), color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: Metrics.hintTextWidth, alignment: .leading)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if !arrowLeading { glossyArrow(arrow, color: color) }
        }
    }

    private func glossyArrow(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: Metrics.hintArrowSize, weight: .light))
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.72), color, color.opacity(0.58)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: color.opacity(0.45), radius: 5)
    }

    private var hintDivider: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.28), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: Metrics.hintDividerHeight)
    }

    private var actionButtons: some View {
        HStack {
            DecisionButton(
                systemImage: "checkmark",
                color: Metrics.controlKeep,
                accessibilityLabel: Strings.Triage.keep
            ) {
                fly(.keep)
            }
            Spacer()
            DecisionButton(
                systemImage: "trash",
                color: Metrics.controlDelete,
                accessibilityLabel: Strings.Triage.delete
            ) {
                fly(.markForDeletion)
            }
        }
        // Overlaying the conditional utility keeps both primary verdict
        // controls anchored, so their tap targets never shift after a swipe.
        .overlay {
            if viewModel.state.canUndo {
                UndoButton(action: undo)
                    .allowsHitTesting(!isDismissing)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            }
        }
        .animation(
            .spring(response: 0.32, dampingFraction: 0.78),
            value: viewModel.state.canUndo
        )
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 4)
    }

    // MARK: - Finished / failure

    private var finished: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(Metrics.keep)
            Text(Strings.Triage.doneTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(Strings.Triage.doneMessage(
                countText(viewModel.state.keptCount),
                countText(viewModel.state.markedCount)
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(Strings.Triage.doneHint)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            if viewModel.state.canUndo {
                UndoButton(action: undo)
                    .allowsHitTesting(!isDismissing)
                    .padding(.top, 8)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            }
            Button(action: requestStartOver) {
                Label(Strings.Triage.restartTriage, systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.white.opacity(0.78))
            .padding(.top, 8)
        }
        .padding(.horizontal, Metrics.screenPadding)
    }

    private var failure: some View {
        ContentUnavailableView {
            Label(Strings.Access.title, systemImage: "lock.fill")
        } description: {
            Text(viewModel.state.errorMessage ?? Strings.Error.generic)
        } actions: {
            if showsOpenSettings {
                Button(Strings.Access.openSettings) { viewModel.send(.openSettings) }
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

    private var progressText: String {
        Strings.Triage.progress(
            countText(min(viewModel.state.currentIndex + 1, viewModel.state.screenshots.count)),
            countText(viewModel.state.screenshots.count)
        )
    }

    private func countText(_ value: Int) -> String {
        Self.counter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func requestStartOver() {
        showStartOverConfirmation = true
    }

    private static let counter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

// MARK: - Design tokens

private enum Metrics {
    static let background = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let keep = Color.blue
    static let delete = Color.red
    static let review = Color.orange
    static let neutral = Color.secondary
    static let controlKeep = Color(red: 0.08, green: 0.43, blue: 0.90)
    static let controlDelete = Color(red: 0.88, green: 0.20, blue: 0.29)
    static let controlUndo = Color(red: 0.48, green: 0.38, blue: 0.95)
    static let cardCornerRadius: CGFloat = 32
    static let cardStroke = Color.white.opacity(0.08)
    static let surfaceFill = Color.white.opacity(0.05)
    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
    static let decisionThreshold: CGFloat = 120
    static let actionButtonSize: CGFloat = 64
    static let actionButtonHaloPadding: CGFloat = 12
    static let undoButtonHeight: CGFloat = 40
    static let undoButtonHorizontalPadding: CGFloat = 12
    static let hintArrowSize: CGFloat = 24
    static let hintArrowSpacing: CGFloat = 10
    static let hintTextWidth: CGFloat = 72
    static let hintGroupSpacing: CGFloat = 12
    static let hintDividerHeight: CGFloat = 32
    static let imageModeTransitionDuration = 0.18
}

// MARK: - Liquid Glass

/// Same treatment as the Overview surfaces: real `glassEffect` on iOS 26,
/// translucent material + hairline border on older systems.
private struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            content
                .background(tint?.opacity(0.2) ?? Metrics.surfaceFill, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(
                        tint?.opacity(0.4) ?? Metrics.cardStroke,
                        lineWidth: 1
                    )
                }
        }
    }
}

private extension View {
    func liquidGlass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint))
    }
}

private struct CircularIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 38, height: 38)
                .liquidGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Card

private struct TriageCardView: View {
    let screenshot: Screenshot
    /// `nil` while the pipeline is still classifying this card.
    let classification: ScreenshotClassification?
    let imageMode: CardImageMode
    let loadThumbnail: (Screenshot.ID, CGSize) async -> UIImage?

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
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
            .overlay(shape.strokeBorder(Metrics.cardStroke, lineWidth: 1))
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
                // Explicitly constrain both layers to the viewport. Without
                // this, the invisible Fill layer can still determine ZStack's
                // layout and make the Fit presentation appear cropped.
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .opacity(imageMode == .fit ? 1 : 0)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(imageMode == .fill ? 1 : 0)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .animation(
                .easeInOut(duration: Metrics.imageModeTransitionDuration),
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
        case .safeToDelete?: (Strings.Triage.safeToDelete, Metrics.delete)
        case .useful?:       (Strings.Triage.worthKeeping, Metrics.keep)
        case .needsReview?:  (Strings.Triage.needsReview, Metrics.review)
        case nil:            (Strings.Triage.analyzing, Metrics.neutral)
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
        [dateText, sizeText].compactMap(\.self).joined(separator: " • ")
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

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(screenshot.byteSize), countStyle: .file)
    }
}

// MARK: - Full-screen viewer

/// Borderless look at one screenshot, for cards whose detail is too small to
/// judge from the deck. Requests a fresh thumbnail at full screen pixels, so
/// text-heavy shots stay legible; the card-sized image stands in while it loads.
private struct ScreenshotViewerView: View {
    let screenshot: Screenshot
    let loadThumbnail: (Screenshot.ID, CGSize) async -> UIImage?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
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
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.Triage.close)
                .padding(Metrics.screenPadding)
            }
            .task {
                let target = CGSize(
                    width: proxy.size.width * displayScale,
                    height: proxy.size.height * displayScale
                )
                image = await loadThumbnail(screenshot.id, target)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Decision affordances

private struct DecisionStamp: View {
    let text: String
    let color: Color
    let angle: Double

    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .heavy))
            .tracking(2)
            .foregroundStyle(color)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
    }
}

private struct DecisionButton: View {
    let systemImage: String
    let color: Color
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: Metrics.actionButtonSize, height: Metrics.actionButtonSize)
                .background(
                    LinearGradient(
                        colors: [color.opacity(0.72), color, color.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.5), color.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.25
                        )
                }
                .shadow(color: color.opacity(0.42), radius: 14, y: 5)
                .padding(Metrics.actionButtonHaloPadding)
                .background(.ultraThinMaterial, in: Circle())
                .background(Color.white.opacity(0.025), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.035), color.opacity(0.055), .black.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                }
                .shadow(color: .black.opacity(0.38), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Compact on-demand utility: violet identifies a reversible action without
/// borrowing the blue Keep or red Delete semantics of the primary controls.
private struct UndoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))
                Text(Strings.Triage.undo)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, Metrics.undoButtonHorizontalPadding)
            .frame(height: Metrics.undoButtonHeight)
            .liquidGlass(in: Capsule(), tint: Metrics.controlUndo.opacity(0.5))
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.38),
                                Metrics.controlUndo.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(
                color: Metrics.controlUndo.opacity(0.32),
                radius: 10,
                y: 4
            )
            // The visible capsule stays compact while its effective touch
            // target meets the 44pt minimum.
            .padding(.vertical, 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Strings.Triage.undo)
    }
}

// MARK: - Empty state

private struct EmptyScreenshotsView: View {
    var body: some View {
        ContentUnavailableView {
            Label(Strings.Triage.emptyTitle, systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(Strings.Triage.emptyMessage)
        }
    }
}

#if DEBUG
@MainActor
private struct TriageView_Previews: PreviewProvider {
    static var previews: some View {
        makePreview()
    }

    private static func makePreview() -> some View {
        let viewModel = AppComposition().makeTriage()
        viewModel.seedForPreview(
            [
                Screenshot(id: "1", pixelWidth: 1179, pixelHeight: 2556, creationDate: .now, byteSize: 1_800_000),
                Screenshot(id: "2", pixelWidth: 1179, pixelHeight: 2556, creationDate: .now.addingTimeInterval(-90_000), byteSize: 2_400_000),
                Screenshot(id: "3", pixelWidth: 1179, pixelHeight: 2556, creationDate: .now.addingTimeInterval(-400_000), byteSize: 3_100_000)
            ],
            categories: ["1": .otp, "2": .receipt, "3": .location]
        )
        return TriageView(viewModel: viewModel)
            .preferredColorScheme(.dark)
    }
}
#endif
