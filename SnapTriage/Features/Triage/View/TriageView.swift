//
//  TriageView.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import SwiftUI

struct TriageView: View {
    @State private var viewModel: TriageViewModel

    init(viewModel: TriageViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private let columns = [
        GridItem(.adaptive(minimum: Spacing.thumbnailMinWidth), spacing: Spacing.gridSpacing)
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Strings.Triage.title)
        }
        .task { viewModel.send(.onAppear) }
        .sheet(isPresented: isRecognitionPresented) {
            TranscriptSheet(
                recognition: viewModel.state.recognition,
                onDone: { viewModel.send(.dismissRecognition) }
            )
        }
    }

    // Drive the sheet from the recognition state; dismissal routes back through send.
    private var isRecognitionPresented: Binding<Bool> {
        Binding(
            get: { viewModel.state.recognition != .idle },
            set: { presented in
                if !presented { viewModel.send(.dismissRecognition) }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state.phase {
        case .idle, .loading:
            ProgressView(Strings.Triage.loading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed:
            PhotoAccessUnavailableView(
                message: viewModel.state.errorMessage ?? Strings.Error.generic,
                showsOpenSettings: showsOpenSettings,
                onOpenSettings: { viewModel.send(.openSettings) },
                onRetry: { viewModel.send(.retry) }
            )

        case .loaded:
            if viewModel.state.screenshots.isEmpty {
                EmptyScreenshotsView()
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.gridSpacing) {
                ForEach(viewModel.state.screenshots) { screenshot in
                    ScreenshotThumbnailView(
                        screenshot: screenshot,
                        loadThumbnail: { id, size in
                            await viewModel.thumbnail(for: id, targetSize: size)
                        },
                        onSelect: { viewModel.send(.recognize(screenshot.id)) }
                    )
                }
            }
            .padding(Spacing.gridSpacing)
        }
    }

    // Offer Settings only after an actual denial, not while the prompt is undetermined.
    private var showsOpenSettings: Bool {
        let auth = viewModel.state.authorization
        return !auth.canAccessLibrary && auth != .notDetermined
    }
}

private struct PhotoAccessUnavailableView: View {
    let message: String
    let showsOpenSettings: Bool
    let onOpenSettings: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(Strings.Access.title, systemImage: "lock.fill")
        } description: {
            Text(message)
        } actions: {
            if showsOpenSettings {
                Button(Strings.Access.openSettings, action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
            }
            Button(Strings.Access.retry, action: onRetry)
        }
    }
}

private struct TranscriptSheet: View {
    let recognition: TriageViewModel.Recognition
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Strings.Transcript.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.Transcript.done, action: onDone)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var content: some View {
        switch recognition {
        case .idle, .recognizing:
            ProgressView(Strings.Transcript.recognizing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready(let result):
            if result.isEmpty {
                ContentUnavailableView(Strings.Transcript.empty, systemImage: "text.viewfinder")
            } else {
                ScrollView {
                    Text(result.transcript)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }

        case .failed:
            ContentUnavailableView(Strings.Transcript.failed, systemImage: "exclamationmark.triangle")
        }
    }
}

private struct EmptyScreenshotsView: View {
    var body: some View {
        ContentUnavailableView {
            Label(Strings.Triage.emptyTitle, systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(Strings.Triage.emptyMessage)
        }
    }
}
