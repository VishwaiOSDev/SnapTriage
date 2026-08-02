//
//  SettingsViewModelTests.swift
//  SnapTriageTests
//
//  Created by Vishweshwaran on 01/08/26.
//

import Testing
import UserNotifications
@testable import SnapTriage

@MainActor
@Suite("Settings view model")
struct SettingsViewModelTests {

    private func makeSUT(
        authorization: PhotoLibraryAuthorization = .authorized,
        notificationStatus: UNAuthorizationStatus = .authorized,
        cached: [Screenshot.ID: ScreenshotCategory] = ["1": .social, "2": .receipt]
    ) -> (SettingsViewModel, StubSettingsRouter, InMemoryOCRStore) {
        let service = FakePhotoLibraryService(authorization: authorization)
        let ocr = InMemoryOCRStore()
        let router = StubSettingsRouter()
        let vm = SettingsViewModel(
            requestAccess: RequestPhotoAccessUseCase(service: service),
            cache: ManageClassificationCacheUseCase(
                classifyLibrary: Fixture.classifyLibrary(
                    service: service,
                    store: SeededCategoryStore(cached)
                ),
                ocr: ocr
            ),
            notifications: StubNotificationSettingsReader(status: notificationStatus),
            router: router
        )
        return (vm, router, ocr)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, ticks: Int = 5000) async {
        var count = 0
        while !condition() && count < ticks {
            await Task.yield()
            count += 1
        }
    }

    @Test("Opening Settings reads status without prompting")
    func readsStatusWithoutPrompting() async {
        let (vm, _, _) = makeSUT(authorization: .limited, notificationStatus: .denied)

        vm.send(.onAppear)
        await waitUntil { vm.state.cachedCount == 2 }

        #expect(vm.state.authorization == .limited)
        #expect(vm.state.isLimitedAccess)
        #expect(!vm.state.notificationsEnabled)
    }

    @Test("Clearing the cache empties both the classifications and the transcripts")
    func clearingCacheEmptiesBothStores() async {
        let (vm, _, ocr) = makeSUT()
        await ocr.save(OCRResult(screenshotID: "1", lines: []))
        vm.send(.onAppear)
        await waitUntil { vm.state.cachedCount == 2 }

        vm.send(.clearCache)
        await waitUntil { vm.state.cachedCount == 0 && !vm.state.isClearingCache }

        #expect(await ocr.result(for: "1") == nil)
    }

    @Test("Adding photos goes through the limited picker, not the Settings app")
    func addMorePhotosPresentsThePicker() {
        let (vm, router, _) = makeSUT(authorization: .limited)

        vm.send(.addMorePhotos)

        #expect(router.limitedPickerCount == 1)
        #expect(router.systemSettingsCount == 0)
    }
}

@MainActor
private final class StubSettingsRouter: SettingsRouter {
    private(set) var systemSettingsCount = 0
    private(set) var limitedPickerCount = 0

    func openSystemSettings() { systemSettingsCount += 1 }
    func presentLimitedLibraryPicker() { limitedPickerCount += 1 }
}

@MainActor
private struct StubNotificationSettingsReader: NotificationSettingsReading {
    let status: UNAuthorizationStatus
    func authorizationStatus() async -> UNAuthorizationStatus { status }
}
