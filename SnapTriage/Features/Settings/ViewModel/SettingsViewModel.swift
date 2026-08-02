//
//  SettingsViewModel.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 01/08/26.
//

import Foundation
import Observation
import UserNotifications

/// Reads the notification permission without owning it. The request itself stays
/// with the background coordinator, which knows when asking is warranted.
@MainActor
protocol NotificationSettingsReading: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
}

@MainActor
struct SystemNotificationSettingsReader: NotificationSettingsReading {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
}

@MainActor
@Observable
final class SettingsViewModel {

    struct State: Equatable {
        var authorization: PhotoLibraryAuthorization = .notDetermined
        var notificationStatus: UNAuthorizationStatus = .notDetermined
        var cachedCount = 0
        var isClearingCache = false

        var isLimitedAccess: Bool { authorization == .limited }

        var notificationsEnabled: Bool {
            switch notificationStatus {
            case .authorized, .provisional, .ephemeral: true
            default: false
            }
        }
    }

    enum Input {
        case onAppear
        case openSystemSettings
        case addMorePhotos
        case clearCache
    }

    private(set) var state = State()

    private let requestAccess: RequestPhotoAccessUseCase
    private let cache: ManageClassificationCacheUseCase
    private let notifications: NotificationSettingsReading
    private let router: SettingsRouter

    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        requestAccess: RequestPhotoAccessUseCase,
        cache: ManageClassificationCacheUseCase,
        notifications: NotificationSettingsReading,
        router: SettingsRouter
    ) {
        self.requestAccess = requestAccess
        self.cache = cache
        self.notifications = notifications
        self.router = router
    }

    func send(_ input: Input) {
        switch input {
        case .onAppear:
            refresh()
        case .openSystemSettings:
            router.openSystemSettings()
        case .addMorePhotos:
            router.presentLimitedLibraryPicker()
        case .clearCache:
            clearCache()
        }
    }

    private func refresh() {
        // Reading, never prompting: opening Settings must not fire a system
        // dialog the user did not ask for.
        state.authorization = requestAccess.current()
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            let status = await self.notifications.authorizationStatus()
            let count = await self.cache.cachedCount()
            guard !Task.isCancelled else { return }
            self.state.notificationStatus = status
            self.state.cachedCount = count
        }
    }

    private func clearCache() {
        guard !state.isClearingCache else { return }
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            self.state.isClearingCache = true
            defer { self.state.isClearingCache = false }
            await self.cache.clear()
            guard !Task.isCancelled else { return }
            self.state.cachedCount = await self.cache.cachedCount()
        }
    }

    deinit {
        task?.cancel()
    }
}
