//
//  TriageView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

struct TriageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TriageViewModel
    private let onReview: () -> Void
    private let onBulkTriage: () -> Void

    /// Drag state is pure UI: it lives in the view and never reaches the
    /// ViewModel. Only the final decision crosses the boundary via `send`.
    @State private var drag: CGSize = .zero
    /// Translation reported by the first `onChanged`. Subtracting it keeps the
    /// card pinned to the finger instead of teleporting by the activation
    /// distance the moment the gesture is claimed.
    @State private var dragAnchor: CGSize?
    /// Furthest the finger has travelled this gesture, so a swipe that returns
    /// to centre is never mistaken for a tap.
    @State private var dragTravel: CGFloat = 0
    @State private var isDismissing = false
    @State private var isUndoing = false
    @State private var fullScreenShot: Screenshot?

    @AppStorage(CardImageMode.storageKey) private var imageMode: CardImageMode = .fit
    @State private var showStartOverConfirmation = false

    /// Shared and prepared ahead of the first swipe: creating a generator and
    /// firing it cold spins up the haptic engine, which stalls the first fly-off.
    @State private var haptic = UIImpactFeedbackGenerator(style: .medium)
    @State private var undoHaptic = UIImpactFeedbackGenerator(style: .soft)

    init(
        viewModel: TriageViewModel,
        onReview: @escaping () -> Void = {},
        onBulkTriage: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onReview = onReview
        self.onBulkTriage = onBulkTriage
    }

    var body: some View {
        // The triage session is presented as a cover, so it brings its own
        // navigation context: the bar carries the title, progress, close, and
        // overflow that the deck used to draw by hand.
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                content
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TriageTitleView(
                        phase: viewModel.state.phase,
                        decidedCount: viewModel.state.decidedIDs.count,
                        totalCount: viewModel.state.screenshots.count
                    )
                    .equatable()
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Strings.Triage.close)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    TriageOverflowMenu(
                        imageMode: imageMode,
                        canStartOver: viewModel.state.hasProgress && !viewModel.state.isFinished,
                        onBulkTriage: onBulkTriage,
                        onToggleImageMode: {
                            withAnimation(.easeInOut(duration: TriageMetrics.imageModeTransitionDuration)) {
                                imageMode = imageMode.toggled
                            }
                        },
                        onStartOver: requestStartOver,
                        onRecategorizeAll: { viewModel.send(.recategorizeAll) }
                    )
                    .equatable()
                }
            }
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
            status { ProgressView(Strings.Triage.loading) }

        case .failed:
            status { failure }

        case .loaded:
            if viewModel.state.screenshots.isEmpty {
                status { EmptyScreenshotsView() }
            } else if viewModel.state.isFinished {
                status { finished }
            } else {
                deck
            }
        }
    }

    // Centers a non-deck state in the space below the navigation bar.
    private func status<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        inner()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Spacing.screenPadding)
    }

    private var deck: some View {
        VStack(spacing: TriageMetrics.sectionSpacing) {
            categoryPill
            cardStack
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            SwipeHintsView()
            actionButtons
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, TriageMetrics.sectionSpacing)
        .padding(.bottom, TriageMetrics.sectionSpacing)
    }

    // MARK: - Card stack

    @ViewBuilder
    private var categoryPill: some View {
        if let current = viewModel.state.current {
            // Pending classification shows a neutral "Analyzing…" pill — never a
            // premature category or safe-to-delete verdict.
            let classification = viewModel.classification(for: current)
            HStack(spacing: 6) {
                Image(systemName: classification?.category.systemImage ?? "hourglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.keep)
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

    // A ForEach keyed by screenshot id keeps view identity stable while a card
    // moves from the back slot to the front, so its already-loaded thumbnail
    // survives the promotion instead of flashing back to the placeholder.
    private var cardStack: some View {
        ZStack {
            ForEach(deckWindow) { screenshot in
                deckCard(for: screenshot, isTop: screenshot.id == viewModel.state.current?.id)
            }
        }
        // The drag must be measured against the deck, which never moves. In the
        // gesture's own (default) local space the card is being offset and
        // rotated by the very values being read, which skews the translation.
        .coordinateSpace(.named(Self.deckSpace))
    }

    private static let deckSpace = "triage.deck"

    private func deckCard(for screenshot: Screenshot, isTop: Bool) -> some View {
        let scale: CGFloat = isTop
            ? 1 - min(abs(drag.width) / 2400, 0.04)
            : 0.92 + 0.08 * dragProgress
        let rotation: Double = isTop ? Double(drag.width / 18) : 0
        return card(for: screenshot, onTap: isTop ? { fullScreenShot = screenshot } : {})
            .overlay { if isTop && !isUndoing { decisionStamps } }
            .scaleEffect(scale)
            .opacity(isTop ? 1 : 0.6 + 0.4 * Double(dragProgress))
            .offset(isTop ? drag : .zero)
            .rotationEffect(.degrees(rotation), anchor: .bottom)
            .gesture(isTop ? dragGesture(for: screenshot) : nil)
    }

    // Back-to-front render order: up-next behind, current on top.
    private var deckWindow: [Screenshot] {
        [viewModel.upNext, viewModel.state.current].compactMap(\.self)
    }

    private func card(for screenshot: Screenshot, onTap: @escaping () -> Void) -> some View {
        TriageCardView(
            screenshot: screenshot,
            classification: viewModel.classification(for: screenshot),
            imageMode: imageMode,
            loadThumbnail: { id, size in
                await viewModel.thumbnail(for: id, targetSize: size)
            },
            onTap: onTap
        )
    }

    private var decisionStamps: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: TriageMetrics.cardCornerRadius, style: .continuous)
                .fill(stampColor.opacity(0.25 * Double(dragProgress)))
            HStack {
                DecisionStamp(text: Strings.Triage.keepBadge, color: Palette.keep, angle: -12)
                    .opacity(drag.width > 0 ? Double(dragProgress) : 0)
                Spacer()
                DecisionStamp(text: Strings.Triage.deleteBadge, color: Palette.delete, angle: 12)
                    .opacity(drag.width < 0 ? Double(dragProgress) : 0)
            }
            .padding(24)
        }
        .allowsHitTesting(false)
    }

    private var stampColor: Color {
        drag.width >= 0 ? Palette.keep : Palette.delete
    }

    private var dragProgress: CGFloat {
        min(max((abs(drag.width) - 16) / (TriageMetrics.decisionThreshold - 16), 0), 1)
    }

    // MARK: - Gesture

    /// One recognizer owns the whole card: `minimumDistance: 0` so the card
    /// leaves centre on the first touch, and a tap is read on release from how
    /// little the finger moved. A separate `onTapGesture` on the card would sit
    /// below this one in the hierarchy, take priority, and hold the drag back
    /// until it failed — which is what made the swipe feel late.
    private func dragGesture(for screenshot: Screenshot) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.deckSpace))
            .onChanged { value in
                guard !isDismissing else { return }
                let anchor = dragAnchor ?? value.translation
                if dragAnchor == nil { dragAnchor = anchor }
                drag = CGSize(
                    width: value.translation.width - anchor.width,
                    height: value.translation.height - anchor.height
                )
                dragTravel = max(dragTravel, hypot(drag.width, drag.height))
            }
            .onEnded { _ in
                let travel = dragTravel
                let width = drag.width
                dragAnchor = nil
                dragTravel = 0

                guard !isDismissing else { return }
                if width > TriageMetrics.decisionThreshold {
                    fly(.keep)
                } else if width < -TriageMetrics.decisionThreshold {
                    fly(.markForDeletion)
                } else {
                    if travel < TriageMetrics.tapSlop {
                        fullScreenShot = screenshot
                    }
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
            dragAnchor = nil
            dragTravel = 0
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

    // MARK: - Actions

    private var actionButtons: some View {
        HStack {
            DecisionButton(
                systemImage: "checkmark",
                color: Palette.controlKeep,
                accessibilityLabel: Strings.Triage.keep
            ) {
                fly(.keep)
            }
            Spacer()
            DecisionButton(
                systemImage: "trash",
                color: Palette.controlDelete,
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
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, 4)
    }

    // MARK: - Finished / failure

    private var finished: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(Palette.keep)
            Text(Strings.Triage.doneTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(Strings.Triage.doneMessage(
                MetricFormatter.count(viewModel.state.keptCount),
                MetricFormatter.count(viewModel.state.markedCount)
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(Strings.Triage.doneHint)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            // The marked set is waiting in Review; hand the user straight there
            // instead of relying on a tab they'd have to find.
            if viewModel.state.markedCount > 0 {
                Button(action: onReview) {
                    Label(Strings.Review.title, systemImage: "trash")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.controlDelete)
                .padding(.top, 12)
            }
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
        .padding(.horizontal, Spacing.screenPadding)
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

    private func requestStartOver() {
        showStartOverConfirmation = true
    }
}

// MARK: - Navigation bar

/// Title and pass progress, split out of `TriageView` so the bar diffs on these
/// three values instead of on the whole view model.
///
/// `.toolbar` bridges to `UIBarButtonItem`/`UINavigationItem`. Rebuilding those
/// under a live presentation is what made the overflow menu flicker and swallow
/// the tap that opened it, so nothing that moves at pipeline frequency may reach
/// this far.
private struct TriageTitleView: View, Equatable {
    let phase: TriageViewModel.Phase
    let decidedCount: Int
    let totalCount: Int

    var body: some View {
        // Progress belongs with the title, so a two-line principal item stands
        // in for `navigationSubtitle`, which needs iOS 26.
        VStack(spacing: 2) {
            Text(Strings.Triage.title)
                .font(.headline)
                .foregroundStyle(.white)
            if phase == .loaded, totalCount > 0 {
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .animation(.default, value: decidedCount)
    }

    // Counts verdicts given, not the cursor's position: the deck surfaces
    // classified cards first, so the index no longer advances monotonically.
    private var progressText: String {
        Strings.Triage.progress(
            MetricFormatter.count(min(decidedCount + 1, totalCount)),
            MetricFormatter.count(totalCount)
        )
    }
}

private struct TriageOverflowMenu: View, Equatable {
    let imageMode: CardImageMode
    /// Only offer a mid-pass restart while there is progress to discard; the
    /// finished screen already exposes its own restart control.
    let canStartOver: Bool
    let onBulkTriage: () -> Void
    let onToggleImageMode: () -> Void
    let onStartOver: () -> Void
    let onRecategorizeAll: () -> Void

    /// Closures never compare equal, so leaving this to SwiftUI's own diffing
    /// would re-run `body` — and rebuild the menu — on every parent update.
    /// Identity here is the value inputs alone.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.imageMode == rhs.imageMode && lhs.canStartOver == rhs.canStartOver
    }

    var body: some View {
        Menu {
            // 1,200 screenshots is 1,200 swipes only if the classifier's work is
            // thrown away. Hand the user the escape hatch from inside the deck,
            // where the tedium is actually felt.
            Button(action: onBulkTriage) {
                Label(Strings.Categories.title, systemImage: "square.stack.3d.up")
            }

            Divider()

            Button(action: onToggleImageMode) {
                Label(
                    imageMode == .fill
                        ? Strings.Triage.fitImage
                        : Strings.Triage.fillImage,
                    systemImage: imageMode == .fill
                        ? "arrow.down.forward.and.arrow.up.backward"
                        : "arrow.up.left.and.arrow.down.right"
                )
            }

            if canStartOver {
                Divider()
                // This only opens a confirmation; reserve destructive red for
                // the action that actually clears the pass.
                Button(action: onStartOver) {
                    Label(Strings.Triage.restartTriage, systemImage: "arrow.counterclockwise")
                }
            }

            #if DEBUG
            Divider()
            // Wipes the classification cache and re-runs the pipeline. Debug-only:
            // for exercising categorization (and the background pass) end to end.
            Button(action: onRecategorizeAll) {
                Label("Re-categorize all (debug)", systemImage: "wand.and.stars")
            }
            #endif
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Strings.Triage.more)
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
