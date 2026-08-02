//
//  BackgroundClassificationCoordinator.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 13/07/26.
//

import BackgroundTasks
import Foundation
import OSLog
import UIKit
import UserNotifications

/// Owns completion of a whole-library classification pass after the app moves
/// to the background. The UIKit assertion is only a short bridge; the
/// BGProcessingTask is the durable, system-scheduled continuation.
///
/// Foreground features and this coordinator all use the same
/// ``LibraryClassificationEngine``. Their requests therefore join in-flight OCR
/// and categorization instead of doing the same expensive work more than once.
@MainActor
final class BackgroundClassificationCoordinator {

    static let taskIdentifier = "dev.vishwaiosdev.SnapTriage.classify"

    struct PassResult: Equatable {
        enum Outcome: Equatable {
            case completed
            case cancelled
            case failed
        }

        let outcome: Outcome
        let newlyClassified: Int
        let remaining: Int
        let notificationPending: Bool

        var succeeded: Bool {
            outcome == .completed && remaining == 0 && !notificationPending
        }
    }

    private struct ActivePass {
        let id: UUID
        let task: Task<PassResult, Never>
    }

    private struct Bridge {
        let id: UUID
        let backgroundGeneration: Int
        let task: Task<Void, Never>
    }

    private let loadScreenshots: LoadScreenshotsUseCase
    private let classifyLibrary: ClassifyLibraryUseCase
    private let decisions: TriageDecisionStore
    private let notifier: ClassificationNotifying
    private let completionStore: ClassificationCompletionStoring
    private let presenter: ForegroundNotificationPresenter
    private let assertion: BackgroundTaskAssertion
    private let logger = Logger(subsystem: "dev.vishwaiosdev.SnapTriage", category: "BackgroundClassification")

    private var activePass: ActivePass?
    private var bridge: Bridge?
    private var activeSystemTasks = 0
    private var isBackgrounded = false
    private var backgroundGeneration = 0

    init(
        loadScreenshots: LoadScreenshotsUseCase,
        classifyLibrary: ClassifyLibraryUseCase,
        decisions: TriageDecisionStore,
        notifier: ClassificationNotifying? = nil,
        completionStore: ClassificationCompletionStoring? = nil,
        assertion: BackgroundTaskAssertion? = nil,
        onOpenTriage: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.loadScreenshots = loadScreenshots
        self.classifyLibrary = classifyLibrary
        self.decisions = decisions
        self.notifier = notifier ?? ClassificationNotifier()
        self.completionStore = completionStore ?? UserDefaultsClassificationCompletionStore()
        self.assertion = assertion ?? BackgroundTaskAssertion()
        presenter = ForegroundNotificationPresenter(onOpenTriage: onOpenTriage)
    }

    /// Must be called synchronously during app launch, before the scene connects.
    func registerLaunchHandler() {
        UNUserNotificationCenter.current().delegate = presenter
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            guard let self else {
                processingTask.setTaskCompleted(success: false)
                return
            }
            self.handle(processingTask)
        }

        if !registered {
            logger.error("BGTaskScheduler rejected registration for \(Self.taskIdentifier, privacy: .public)")
        }
    }

    func requestNotificationAuthorization() async {
        do {
            try await notifier.requestAuthorizationIfNeeded()
            _ = await deliverPendingNotificationIfPossible()
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleAppDidBackground() {
        isBackgrounded = true
        backgroundGeneration += 1
        scheduleClassificationPass()
        startBridgePass(for: backgroundGeneration)
    }

    func handleAppWillEnterForeground() {
        isBackgrounded = false
        bridge?.task.cancel()
        assertion.end()

        // A system-owned task must be allowed to finish even if a scene becomes
        // active. Otherwise foregrounding can incorrectly fail a BGProcessingTask.
        if activeSystemTasks == 0 {
            activePass?.task.cancel()
        }

        Task { [weak self] in
            _ = await self?.deliverPendingNotificationIfPossible()
        }
    }

    /// Internal so the durability and completion contract can be exercised by
    /// unit tests without trying to simulate BGTaskScheduler.
    func runClassificationPass() async -> PassResult {
        if let activePass {
            return await activePass.task.value
        }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return PassResult(
                    outcome: .failed,
                    newlyClassified: 0,
                    remaining: 0,
                    notificationPending: false
                )
            }
            return await self.performClassificationPass()
        }
        activePass = ActivePass(id: id, task: task)
        let result = await task.value
        if activePass?.id == id {
            activePass = nil
        }
        return result
    }

    private func scheduleClassificationPass() {
        // Keep at most one pending request. Repeated scene transitions otherwise
        // eventually hit BGTaskScheduler's pending-request quota.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Unable to submit background classification: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cancelScheduledPass() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    private func startBridgePass(for generation: Int) {
        guard bridge == nil else { return }

        let id = UUID()
        assertion.begin(name: "classification-bridge") { [weak self] in
            self?.expireBridge(id: id)
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.runClassificationPass()
            self.finishBridge(id: id, generation: generation, result: result)
        }
        bridge = Bridge(id: id, backgroundGeneration: generation, task: task)
    }

    private func expireBridge(id: UUID) {
        guard bridge?.id == id else { return }
        bridge?.task.cancel()
        if activeSystemTasks == 0 {
            activePass?.task.cancel()
        }
    }

    private func finishBridge(id: UUID, generation: Int, result: PassResult) {
        guard bridge?.id == id else { return }
        bridge = nil
        assertion.end()

        if result.remaining == 0 && !result.notificationPending {
            cancelScheduledPass()
        }

        // Foreground -> background can happen again before a cancelled bridge
        // unwinds. Token/generation checks keep the stale completion from
        // clearing or replacing the newer lifecycle's work.
        if isBackgrounded, backgroundGeneration > generation {
            startBridgePass(for: backgroundGeneration)
        }
    }

    private func handle(_ task: BGProcessingTask) {
        activeSystemTasks += 1
        // Schedule the successor at the start. If this pass drains the work it
        // is cancelled on completion; if iOS expires us, the remainder has a
        // pending request without relying on code after expiration.
        scheduleClassificationPass()

        let work = Task { @MainActor [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            let result = await self.runClassificationPass()
            self.activeSystemTasks = max(0, self.activeSystemTasks - 1)
            if result.remaining == 0 && !result.notificationPending {
                self.cancelScheduledPass()
            }
            task.setTaskCompleted(success: result.succeeded)
        }

        task.expirationHandler = { [weak self] in
            work.cancel()
            Task { @MainActor in
                guard let self else { return }
                self.activePass?.task.cancel()
            }
        }
    }

    private func performClassificationPass() async -> PassResult {
        classifyLibrary.prewarm()

        let screenshots: [Screenshot]
        do {
            screenshots = try await loadScreenshots.execute()
        } catch is CancellationError {
            await classifyLibrary.flush()
            return resultAfterFailure(.cancelled)
        } catch {
            logger.error("Unable to load screenshots: \(error.localizedDescription, privacy: .public)")
            await classifyLibrary.flush()
            return resultAfterFailure(.failed)
        }

        let cachedAtStart = await classifyLibrary.cachedClassifications()
        let pending = screenshots.filter { cachedAtStart[$0.id] == nil }
        var newlyClassified = 0
        var wasCancelled = Task.isCancelled

        if !pending.isEmpty, !wasCancelled {
            for await progress in classifyLibrary.execute(pending) {
                if progress.resolution == .classified {
                    newlyClassified += 1
                }
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }
            }
        }

        // Persist before reporting success or submitting the notification. A
        // notification must never promise work that still lives only in a
        // write-behind buffer and can disappear when the process is suspended.
        await classifyLibrary.flush()

        let finalCache = await classifyLibrary.cachedClassifications()
        let remaining = screenshots.reduce(into: 0) { count, screenshot in
            if finalCache[screenshot.id] == nil { count += 1 }
        }

        // `pending` may have been completed by a foreground subscriber that
        // joined the same engine operation, so don't key the notification on
        // this consumer's `.classified` counter. If this pass observed work and
        // the durable cache is now complete, the completion signal is owed.
        if !pending.isEmpty, remaining == 0 {
            let verdicts = decisions.allDecisions()
            let readyCount = screenshots.reduce(into: 0) { count, screenshot in
                if finalCache[screenshot.id] != nil, verdicts[screenshot.id] == nil {
                    count += 1
                }
            }
            if readyCount > 0 {
                completionStore.savePendingCount(readyCount)
            }
        }

        let notificationPending = await deliverPendingNotificationIfPossible()
        let outcome: PassResult.Outcome
        if remaining == 0 {
            outcome = .completed
        } else if wasCancelled {
            outcome = .cancelled
        } else {
            outcome = .failed
        }

        return PassResult(
            outcome: outcome,
            newlyClassified: newlyClassified,
            remaining: remaining,
            notificationPending: notificationPending
        )
    }

    private func resultAfterFailure(_ outcome: PassResult.Outcome) -> PassResult {
        PassResult(
            outcome: outcome,
            newlyClassified: 0,
            remaining: 1,
            notificationPending: completionStore.pendingCount != nil
        )
    }

    /// Returns true while delivery should be retried. Denied permission is an
    /// intentional suppression and clears the debt; notDetermined and transient
    /// delivery errors remain pending for the next foreground/background event.
    private func deliverPendingNotificationIfPossible() async -> Bool {
        guard let count = completionStore.pendingCount else { return false }
        do {
            switch try await notifier.notifyReady(count: count) {
            case .delivered, .suppressed:
                completionStore.clearPendingCount()
                return false
            case .deferred:
                return true
            }
        } catch {
            logger.error("Unable to deliver classification notification: \(error.localizedDescription, privacy: .public)")
            return true
        }
    }
}

@MainActor
protocol ClassificationNotifying {
    func requestAuthorizationIfNeeded() async throws
    func notifyReady(count: Int) async throws -> ClassificationNotificationDelivery
}

enum ClassificationNotificationDelivery {
    case delivered
    case suppressed
    case deferred
}

@MainActor
struct ClassificationNotifier: ClassificationNotifying {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() async throws {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notifyReady(count: Int) async throws -> ClassificationNotificationDelivery {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            return .deferred
        default:
            return .suppressed
        }

        let content = UNMutableNotificationContent()
        content.title = String(
            localized: "notification.classificationReady.title",
            defaultValue: "Screenshots ready to triage"
        )
        content.body = String(
            localized: "notification.classificationReady.body",
            defaultValue: "\(count) screenshots have been sorted. Open SnapTriage to review them."
        )
        content.sound = .default
        content.userInfo = ["destination": "triage"]

        let request = UNNotificationRequest(
            identifier: "classification-ready",
            content: content,
            trigger: nil
        )
        try await center.add(request)
        return .delivered
    }
}

@MainActor
protocol ClassificationCompletionStoring {
    var pendingCount: Int? { get }
    func savePendingCount(_ count: Int)
    func clearPendingCount()
}

@MainActor
final class UserDefaultsClassificationCompletionStore: ClassificationCompletionStoring {
    private static let key = "classification.pendingNotificationCount"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pendingCount: Int? {
        guard defaults.object(forKey: Self.key) != nil else { return nil }
        return defaults.integer(forKey: Self.key)
    }

    func savePendingCount(_ count: Int) {
        defaults.set(count, forKey: Self.key)
    }

    func clearPendingCount() {
        defaults.removeObject(forKey: Self.key)
    }
}

/// Presents the completion banner in the foreground and routes notification
/// taps directly to the Triage tab.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let onOpenTriage: @MainActor @Sendable () -> Void

    init(onOpenTriage: @escaping @MainActor @Sendable () -> Void) {
        self.onOpenTriage = onOpenTriage
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let shouldOpenTriage =
            response.notification.request.identifier == "classification-ready" &&
            response.notification.request.content.userInfo["destination"] as? String == "triage"

        // Never make UserNotifications wait for the main actor while SwiftUI is
        // creating/restoring its scene. Acknowledge the response synchronously;
        // AppNavigation will apply the route once the scene becomes active.
        completionHandler()
        guard shouldOpenTriage else { return }
        Task { @MainActor [onOpenTriage] in
            onOpenTriage()
        }
    }
}

/// A single UIKit background-time assertion for the brief transition from an
/// active scene to suspension. This is best effort and never substitutes for a
/// BGProcessingTask.
@MainActor
final class BackgroundTaskAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private let application: UIApplication

    init(application: UIApplication) {
        self.application = application
    }

    convenience init() {
        self.init(application: .shared)
    }

    func begin(name: String, onExpiration: @escaping @MainActor () -> Void) {
        guard identifier == .invalid else { return }
        identifier = application.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor [weak self] in
                onExpiration()
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        application.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
