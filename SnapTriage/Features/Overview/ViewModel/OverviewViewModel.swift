//
//  OverviewViewModel.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 21/06/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class OverviewViewModel {
    enum Phase: Equatable { case idle, loading, loaded, failed }

    struct State: Equatable {
        var phase: Phase = .idle
        var summary: OverviewSummary = .empty
        var classifiedCount = 0
        var errorMessage: String?
        var authorization: PhotoLibraryAuthorization = .notDetermined
        var features: [FeatureHighlight] = FeatureHighlight.defaults

        var isClassifying: Bool {
            phase == .loaded && summary.totalCount > 0 && classifiedCount < summary.totalCount
        }
    }

    enum Input {
        case onAppear
        case retry
        case openSettings
        case selectFeature(FeatureHighlight.ID)
    }

    private(set) var state = State()

    private let requestAccess: RequestPhotoAccessUseCase
    private let loadScreenshots: LoadScreenshotsUseCase
    private let classifyLibrary: ClassifyLibraryUseCase
    private let router: OverviewRouter

    init(
        requestAccess: RequestPhotoAccessUseCase,
        loadScreenshots: LoadScreenshotsUseCase,
        classifyLibrary: ClassifyLibraryUseCase,
        router: OverviewRouter
    ) {
        self.requestAccess = requestAccess
        self.loadScreenshots = loadScreenshots
        self.classifyLibrary = classifyLibrary
        self.router = router
    }

    func send(_ input: Input) {
        switch input {
        case .openSettings:
            router.openSettings()
        case .onAppear, .retry, .selectFeature:
            break
        }
    }
}
