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
                brandLockup
                hero
                    .padding(.top, 28)
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

    private var brandLockup: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.accent.gradient)

                // Reuse the real Icon Composer artwork so onboarding and the
                // Home Screen establish the same visual identity.
                Image("OnboardingAppIcon")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(2)
            }
            .frame(width: 42, height: 42)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: Palette.accent.opacity(0.18), radius: 8, y: 3)
            .accessibilityHidden(true)

            Text(Strings.Overview.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var hero: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.035))
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 41, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Palette.accent)
            }
            .frame(width: 104, height: 104)

            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Palette.accent.gradient, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.30), radius: 5, y: 2)
                .offset(x: -3, y: -3)
        }
        .accessibilityHidden(true)
    }

    private var introduction: some View {
        VStack(spacing: 10) {
            Text(Strings.Access.primerTitle)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(Strings.Access.primerMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
    }

    private var privacyPromises: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Self.promises, id: \.title) { promise in
                promiseRow(promise)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func promiseRow(_ promise: Promise) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: promise.systemImage)
                .font(.system(size: 22, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Palette.accent)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(promise.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(promise.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var actionArea: some View {
        VStack(spacing: 11) {
            PrimaryActionButton(
                title: Strings.Access.primerContinue,
                systemImage: "chevron.right",
                action: onContinue
            )

            Text(Strings.Access.primerFootnote)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
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
