//
//  TriageViewModel.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class TriageViewModel {

    enum Phase: Equatable { case idle, loading, loaded, failed }

    struct State: Equatable {
        var authorization: PhotoLibraryAuthorization = .notDetermined
        var screenshots: [Screenshot] = []
        var phase: Phase = .idle
        var errorMessage: String?
    }

    enum Input {
        case onAppear
        case retry
        case recognize(Screenshot.ID)
        case openSettings
        case clearError
    }

    private(set) var state = State()

    private let requestAccess: RequestPhotoAccessUseCase
    private let loadScreenshots: LoadScreenshotsUseCase
    private let recognizeText: RecognizeScreenshotTextUseCase
    private let imageLoader: PhotoLibraryService
    private let router: TriageRouter

    private enum TaskKind { case load, ocr }
    @ObservationIgnored private var tasks: [TaskKind: Task<Void, Never>] = [:]

    init(
        requestAccess: RequestPhotoAccessUseCase,
        loadScreenshots: LoadScreenshotsUseCase,
        recognizeText: RecognizeScreenshotTextUseCase,
        imageLoader: PhotoLibraryService,
        router: TriageRouter
    ) {
        self.requestAccess = requestAccess
        self.loadScreenshots = loadScreenshots
        self.recognizeText = recognizeText
        self.imageLoader = imageLoader
        self.router = router
    }

    func send(_ input: Input) {
        switch input {
        case .onAppear, .retry:
            loadFlow()
        case .recognize(let id):
            recognizeFlow(id: id)
        case .openSettings:
            router.openSettings()
        case .clearError:
            state.errorMessage = nil
        }
    }

    // Transient read for grid cells, not domain state, so bypasses send.
    func thumbnail(for id: Screenshot.ID, targetSize: CGSize) async -> UIImage? {
        await imageLoader.thumbnail(for: id, targetSize: targetSize)
    }

    private func loadFlow() {
        run(.load) { [weak self] in
            guard let self else { return }
            self.state.phase = .loading
            self.state.errorMessage = nil

            let authorization = await self.requestAccess.execute()
            self.state.authorization = authorization

            guard authorization.canAccessLibrary else {
                self.state.errorMessage = self.presentAuth(authorization)
                self.state.phase = .failed
                return
            }

            do {
                let screenshots = try await self.loadScreenshots.execute()
                self.state.screenshots = screenshots
                self.state.phase = .loaded
            } catch is CancellationError {
                // superseded by newer load
            } catch {
                self.state.errorMessage = self.present(error)
                self.state.phase = .failed
            }
        }
    }

    private func recognizeFlow(id: Screenshot.ID) {
        run(.ocr) { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.recognizeText.execute(screenshotID: id)
                self.logOCR(result)
            } catch is CancellationError {
                // superseded by a newer tap
            } catch {
                print("[OCR] failed for \(id): \(error)")
            }
        }
    }

    // Stage 2 validation only: log the transcript to confirm OCR quality before Stage 3
    // builds caching and categorization on top. No domain state is mutated yet.
    private func logOCR(_ result: OCRResult) {
        print("""
        ──────── OCR \(result.screenshotID) ────────
        lines: \(result.lines.count)
        \(result.isEmpty ? "(no text recognized)" : result.transcript)
        ─────────────────────────────────────────────
        """)
    }

    // Replaces any in-flight task of the same kind: cancel stale, no reentrancy race.
    private func run(_ kind: TaskKind, _ operation: @escaping () async -> Void) {
        tasks[kind]?.cancel()
        tasks[kind] = Task { await operation() }
    }

    private func present(_ error: Error) -> String {
        switch error {
        case TriageError.photoAccessDenied:     return Strings.Error.accessDenied
        case TriageError.photoAccessRestricted: return Strings.Error.accessRestricted
        default:                                return Strings.Error.generic
        }
    }

    private func presentAuth(_ authorization: PhotoLibraryAuthorization) -> String {
        switch authorization {
        case .denied:     return Strings.Error.accessDenied
        case .restricted: return Strings.Error.accessRestricted
        default:          return Strings.Error.generic
        }
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }
}
