//
//  PhotoLibraryService.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Photos
import UIKit

enum PhotoThumbnailMode: Sendable, Equatable {
    case fit
    case fill
}

protocol PhotoLibraryService: Sendable {
    func currentAuthorization() -> PhotoLibraryAuthorization
    func requestAuthorization() async -> PhotoLibraryAuthorization
    func fetchScreenshots() async -> [Screenshot]
    func thumbnail(
        for id: Screenshot.ID,
        targetSize: CGSize,
        mode: PhotoThumbnailMode
    ) async -> UIImage?
    func cgImage(for id: Screenshot.ID, longEdge: CGFloat) async -> CGImage?
    /// Deletes the given assets from the photo library. iOS presents its own
    /// confirmation sheet; declining it throws `TriageError.deletionCancelled`,
    /// any other failure throws `TriageError.deletionFailed`.
    func deleteScreenshots(_ ids: [Screenshot.ID]) async throws
    /// Emits after the photo library changes (debounced), so features can
    /// refresh instead of showing stale data until relaunch. Each call returns
    /// an independent stream; it never emits without photo access.
    func libraryChanges() -> AsyncStream<Void>
}

// @unchecked Sendable: stored state is PHCachingImageManager (internally
// thread-safe) and the lock-guarded change relay.
final class PhotoKitLibraryService: PhotoLibraryService, @unchecked Sendable {

    private let imageManager = PHCachingImageManager()
    private let changeRelay = LibraryChangeRelay()

    func libraryChanges() -> AsyncStream<Void> {
        changeRelay.makeStream()
    }

    func currentAuthorization() -> PhotoLibraryAuthorization {
        PhotoLibraryAuthorization(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }
    
    func requestAuthorization() async -> PhotoLibraryAuthorization {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return PhotoLibraryAuthorization(status)
    }
    
    func fetchScreenshots() async -> [Screenshot] {
        let options = PHFetchOptions()
        if !Self.includeAllImagesForManualTesting {
            options.predicate = NSPredicate(
                format: "(mediaSubtypes & %d) != 0",
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
        }
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var screenshots: [Screenshot] = []
        screenshots.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            screenshots.append(
                Screenshot(
                    id: asset.localIdentifier,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    creationDate: asset.creationDate,
                    byteSize: Self.byteSize(for: asset)
                )
            )
        }
        return screenshots
    }

    private static var includeAllImagesForManualTesting: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-SnapTriageIncludeAllImages")
        #else
        false
        #endif
    }

    // PHAsset exposes no public size; resource `fileSize` (KVC) is the standard read.
    // Falls back to a 4-bytes-per-pixel estimate when the resource is unavailable (e.g. iCloud-only).
    private static func byteSize(for asset: PHAsset) -> Int {
        let resources = PHAssetResource.assetResources(for: asset)
        if let bytes = resources.compactMap({ $0.value(forKey: "fileSize") as? Int64 }).max() {
            return Int(bytes)
        }
        return asset.pixelWidth * asset.pixelHeight * 4
    }
    
    func thumbnail(
        for id: Screenshot.ID,
        targetSize: CGSize,
        mode: PhotoThumbnailMode
    ) async -> UIImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let contentMode: PHImageContentMode = switch mode {
        case .fit: .aspectFit
        case .fill: .aspectFill
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat    // one final callback, no interim images
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false        // local-only; don't stall on iCloud
        options.isSynchronous = false
        
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, _ in
                once.run { continuation.resume(returning: image) }
            }
        }
    }

    func cgImage(for id: Screenshot.ID, longEdge: CGFloat) async -> CGImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let longestSide = CGFloat(max(asset.pixelWidth, asset.pixelHeight))
        let scale = min(longEdge / longestSide, 1)   // never upscale
        let target = CGSize(
            width: CGFloat(asset.pixelWidth) * scale,
            height: CGFloat(asset.pixelHeight) * scale
        )

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false        // local-only; don't stall on iCloud
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            imageManager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // PhotoKit may fire a degraded interim image first; wait for the final one.
                if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded { return }
                once.run { continuation.resume(returning: image?.cgImage) }
            }
        }
    }

    func deleteScreenshots(_ ids: [Screenshot.ID]) async throws {
        guard !ids.isEmpty else { return }

        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }   // already gone; nothing to do

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
        } catch let error as PHPhotosError where error.code == .userCancelled {
            throw TriageError.deletionCancelled
        } catch {
            throw TriageError.deletionFailed
        }
    }
}

private extension PhotoLibraryAuthorization {
    
    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized:    self = .authorized
        case .limited:       self = .limited
        case .denied:        self = .denied
        case .restricted:    self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default:    self = .denied
        }
    }
}

/// Fans PhotoKit's change callbacks out to any number of `AsyncStream`
/// subscribers. Events are debounced: a screenshot spree or batch delete fires
/// one emission, not one per asset. Deliberately unfiltered — subscribers
/// reload cache-first, so the odd emission for a non-screenshot change costs a
/// cheap fetch, which beats retaining fetch results here just to diff them.
private final class LibraryChangeRelay: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var pendingEmit: Task<Void, Never>?

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func makeStream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id] = nil
                self.lock.unlock()
            }
        }
    }

    // Called by PhotoKit on an arbitrary background queue.
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        lock.lock()
        defer { lock.unlock() }
        guard pendingEmit == nil else { return }
        pendingEmit = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            self?.emit()
        }
    }

    private func emit() {
        lock.lock()
        pendingEmit = nil
        let subscribers = Array(continuations.values)
        lock.unlock()
        subscribers.forEach { $0.yield() }
    }
}

// Guards the continuation: resuming twice traps, and PhotoKit may fire the handler more than once.
private final class ResumeOnce: @unchecked Sendable {
    
    private let lock = NSLock()
    private var hasRun = false
    
    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasRun else { return }
        hasRun = true
        body()
    }
}
