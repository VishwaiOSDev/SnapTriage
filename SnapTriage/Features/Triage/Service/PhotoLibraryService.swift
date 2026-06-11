//
//  PhotoLibraryService.swift
//  SnapTriage
//
//  Created by Vishweshwaran on 07/06/26.
//

import Photos
import UIKit

protocol PhotoLibraryService: Sendable {
    func currentAuthorization() -> PhotoLibraryAuthorization
    func requestAuthorization() async -> PhotoLibraryAuthorization
    func fetchScreenshots() async -> [Screenshot]
    func thumbnail(for id: Screenshot.ID, targetSize: CGSize) async -> UIImage?
    func cgImage(for id: Screenshot.ID, longEdge: CGFloat) async -> CGImage?
}

// @unchecked Sendable: only stored state is PHCachingImageManager, internally thread-safe.
final class PhotoKitLibraryService: PhotoLibraryService, @unchecked Sendable {
    
    private let imageManager = PHCachingImageManager()
    
    func currentAuthorization() -> PhotoLibraryAuthorization {
        PhotoLibraryAuthorization(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }
    
    func requestAuthorization() async -> PhotoLibraryAuthorization {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return PhotoLibraryAuthorization(status)
    }
    
    func fetchScreenshots() async -> [Screenshot] {
        let options = PHFetchOptions()
        // Subtype predicate more robust than "Screenshots" smart album (absent on fresh device).
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
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
                    creationDate: asset.creationDate
                )
            )
        }
        return screenshots
    }
    
    func thumbnail(for id: Screenshot.ID, targetSize: CGSize) async -> UIImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        
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
                contentMode: .aspectFill,
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
