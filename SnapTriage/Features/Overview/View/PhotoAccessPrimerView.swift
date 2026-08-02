//
//  PhotoAccessPrimerView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import SwiftUI

/// Shown once, before the system photo prompt.
///
/// The permission sheet is the single highest-stakes moment in the app: it is
/// asked once, a "Don't Allow" is effectively permanent, and the reassurance
/// that earns the yes — everything stays on device — used to sit behind the very
/// permission being asked for. So the app says what it does and what it will
/// never do first, and only fires the system dialog once the user has agreed to
/// see it.
struct PhotoAccessPrimerView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                introduction
                    .padding(.top, 20)
                privacyPromises
                    .padding(.top, 32)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionArea
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(Palette.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hero: some View {
        Image(systemName: "photo.stack")
            .font(.system(size: 52, weight: .light))
            .foregroundStyle(Palette.accent)
            .accessibilityHidden(true)
    }

    private var introduction: some View {
        VStack(spacing: 8) {
            Text(Strings.Access.primerTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(Strings.Access.primerMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var privacyPromises: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Self.promises, id: \.title) { promise in
                promiseRow(promise)
            }
        }
        .padding(Spacing.cardPadding)
        .liquidGlass(in: RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous))
    }

    private func promiseRow(_ promise: Promise) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: promise.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(promise.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(promise.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actionArea: some View {
        VStack(spacing: 10) {
            PrimaryActionButton(
                title: Strings.Access.primerContinue,
                systemImage: "chevron.right",
                action: onContinue
            )
            Text(Strings.Access.primerFootnote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private struct Promise {
        let systemImage: String
        let title: String
        let detail: String
    }

    private static let promises: [Promise] = [
        Promise(
            systemImage: "iphone",
            title: Strings.Access.primerOnDeviceTitle,
            detail: Strings.Access.primerOnDeviceDetail
        ),
        Promise(
            systemImage: "hand.raised",
            title: Strings.Access.primerNoDeleteTitle,
            detail: Strings.Access.primerNoDeleteDetail
        ),
        Promise(
            systemImage: "square.grid.2x2",
            title: Strings.Access.primerScreenshotsOnlyTitle,
            detail: Strings.Access.primerScreenshotsOnlyDetail
        )
    ]
}

#if DEBUG
private struct PhotoAccessPrimerView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            PhotoAccessPrimerView {}
        }
        .preferredColorScheme(.dark)
    }
}
#endif
