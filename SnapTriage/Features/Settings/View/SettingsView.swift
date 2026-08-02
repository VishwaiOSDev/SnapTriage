//
//  SettingsView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import SwiftUI

/// The app's own settings.
///
/// The gear used to deep-link straight into iOS Settings, which is a reasonable
/// icon for exactly one thing — changing a permission the app cannot change
/// itself — and a misleading one for everything else. Card framing was buried in
/// the deck's overflow menu, the analysis cache had no user-facing control at
/// all, and the privacy claim lived in a pill that could only be read after the
/// permission it was meant to justify. All of it lives here now; the system
/// deep link stays, as one row among several.
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @AppStorage(CardImageMode.storageKey) private var imageMode: CardImageMode = .fit
    @State private var showClearConfirmation = false

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    cardsSection
                    photosSection
                    notificationsSection
                    storageSection
                    privacySection
                    versionFootnote
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.sectionSpacing)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(Strings.Settings.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.send(.onAppear) }
        .sensoryFeedback(.selection, trigger: imageMode)
        .alert(Strings.Settings.clearCacheConfirmTitle, isPresented: $showClearConfirmation) {
            Button(Strings.Triage.cancel, role: .cancel) {}
            Button(Strings.Settings.clearCacheConfirm, role: .destructive) {
                viewModel.send(.clearCache)
            }
        } message: {
            Text(Strings.Settings.clearCacheConfirmMessage)
        }
    }

    // MARK: - Sections

    private var cardsSection: some View {
        SettingsSection(title: Strings.Settings.cardsSection) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(Strings.Settings.imageModeTitle, selection: $imageMode) {
                    ForEach(CardImageMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(Strings.Settings.imageModeFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var photosSection: some View {
        SettingsSection(title: Strings.Settings.photosSection) {
            VStack(spacing: 12) {
                SettingsStatusRow(
                    systemImage: "photo.on.rectangle.angled",
                    title: Strings.Settings.photoAccessTitle,
                    value: accessValue,
                    isWarning: viewModel.state.authorization != .authorized
                )
                if viewModel.state.isLimitedAccess {
                    Text(Strings.Access.limitedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsActionRow(title: Strings.Access.limitedAction) {
                        viewModel.send(.addMorePhotos)
                    }
                }
                SettingsActionRow(title: Strings.Access.openSettings) {
                    viewModel.send(.openSystemSettings)
                }
            }
        }
    }

    private var notificationsSection: some View {
        SettingsSection(title: Strings.Settings.notificationsSection) {
            VStack(spacing: 12) {
                SettingsStatusRow(
                    systemImage: "bell.badge",
                    title: Strings.Settings.notificationsTitle,
                    value: viewModel.state.notificationsEnabled
                        ? Strings.Settings.statusOn
                        : Strings.Settings.statusOff,
                    isWarning: !viewModel.state.notificationsEnabled
                )
                Text(Strings.Settings.notificationsFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SettingsActionRow(title: Strings.Access.openSettings) {
                    viewModel.send(.openSystemSettings)
                }
            }
        }
    }

    private var storageSection: some View {
        SettingsSection(title: Strings.Settings.storageSection) {
            VStack(spacing: 12) {
                SettingsStatusRow(
                    systemImage: "internaldrive",
                    title: Strings.Settings.cachedAnalysisTitle,
                    value: Strings.Settings.cachedAnalysisValue(countText(viewModel.state.cachedCount)),
                    isWarning: false
                )
                Text(Strings.Settings.clearCacheFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SettingsActionRow(
                    title: Strings.Settings.clearCache,
                    role: .destructive,
                    isBusy: viewModel.state.isClearingCache
                ) {
                    showClearConfirmation = true
                }
                .disabled(viewModel.state.cachedCount == 0 || viewModel.state.isClearingCache)
            }
        }
    }

    private var privacySection: some View {
        SettingsSection(title: Strings.Settings.privacySection) {
            VStack(alignment: .leading, spacing: 8) {
                Label(Strings.Overview.privacy, systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(Strings.Settings.privacyStatement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var versionFootnote: some View {
        Text(Strings.Settings.version(Self.versionText))
            .font(.caption2)
            .foregroundStyle(.quaternary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: - Display

    private var accessValue: String {
        switch viewModel.state.authorization {
        case .authorized:    Strings.Settings.accessFull
        case .limited:       Strings.Settings.accessLimited
        case .denied:        Strings.Settings.accessDenied
        case .restricted:    Strings.Settings.accessRestricted
        case .notDetermined: Strings.Settings.accessNotDetermined
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private func countText(_ value: Int) -> String {
        Self.counter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let counter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

// MARK: - Building blocks

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.6)
                .padding(.leading, 4)
            GlassCard {
                content
                    .padding(Spacing.cardPadding)
            }
        }
    }
}

private struct SettingsStatusRow: View {
    let systemImage: String
    let title: String
    let value: String
    let isWarning: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isWarning ? .orange : Palette.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsActionRow: View {
    let title: String
    var role: ButtonRole?
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy { ProgressView().controlSize(.small) }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Palette.delete : Palette.accent)
    }
}
