//
//  OverviewView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import SwiftUI

struct OverviewView: View {
    @State private var viewModel: OverviewViewModel
    private let onStartTriage: () -> Void

    init(viewModel: OverviewViewModel, onStartTriage: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onStartTriage = onStartTriage
    }

    var body: some View {
        ZStack {
            Metrics.background.ignoresSafeArea()
            content
        }
        .task { viewModel.send(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state.phase {
        case .idle, .loading:
            chrome { ProgressView(Strings.Triage.loading) }
        case .failed:
            chrome { failure }
        case .loaded:
            if viewModel.state.summary.totalCount == 0 {
                chrome { EmptyOverviewView() }
            } else {
                chrome { Text(Strings.Overview.reclaimableHeadline).foregroundStyle(.white) }
            }
        }
    }

    private func chrome<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        VStack(spacing: Metrics.sectionSpacing) {
            header
            inner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, Metrics.screenPadding)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppMarkView()
            Text(Strings.Overview.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            CircularIconButton(systemImage: "gearshape.fill", accessibilityLabel: Strings.Overview.settings) {
                viewModel.send(.openSettings)
            }
        }
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

    private var showsOpenSettings: Bool {
        let auth = viewModel.state.authorization
        return !auth.canAccessLibrary && auth != .notDetermined
    }
}

private enum Metrics {
    static let background = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let accent = Color.blue
    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    static let surfaceFill = Color.white.opacity(0.05)
}

private struct AppMarkView: View {
    var body: some View {
        Image(systemName: "doc.text.viewfinder")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Metrics.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                .background(Metrics.surfaceFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct EmptyOverviewView: View {
    var body: some View {
        ContentUnavailableView {
            Label(Strings.Triage.emptyTitle, systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(Strings.Triage.emptyMessage)
        }
    }
}

#Preview {
    let viewModel = OverviewComposition.make(router: SystemOverviewRouter())
    viewModel.seedForPreview(.sample)
    return OverviewView(viewModel: viewModel) {}
}
