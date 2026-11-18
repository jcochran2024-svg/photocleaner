import Photos
import UIKit
import AVFoundation

enum MediaFilter: String, CaseIterable, Identifiable, Codable {
    case all, photos, videos, screenshots
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .photos: return "Photos"
        case .videos: return "Videos"
        case .screenshots: return "Screenshots"
        }
    }
}

/// All PhotoKit access lives here. Everything stays on the device.
enum PhotoLibrary {
    static let imageManager = PHCachingImageManager()

    // MARK: Permission

    static func status() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: Fetching

    /// Fetches assets lazily (PHFetchResult does not load images into memory).
    static func fetch(media: MediaFilter = .all,
                      from: Date? = nil,
                      to: Date? = nil,
                      oldestFirst: Bool = false) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: oldestFirst)]
        options.includeHiddenAssets = false

        var predicates: [NSPredicate] = []
        switch media {
        case .all:
            predicates.append(NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                          PHAssetMediaType.image.rawValue,
                                          PHAssetMediaType.video.rawValue))
        case .photos, .screenshots:
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
        case .videos:
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
        }
        if let from {
            predicates.append(NSPredicate(format: "creationDate >= %@", from as NSDate))
        }
        if let to {
            predicates.append(NSPredicate(format: "creationDate <= %@", to as NSDate))
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        if media == .screenshots {
            let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                                 subtype: .smartAlbumScreenshots,
                                                                 options: nil)
            if let album = albums.firstObject {
                return PHAsset.fetchAssets(in: album, options: options)
            }
        }
        return PHAsset.fetchAssets(with: options)
    }

    static func toArray(_ result: PHFetchResult<PHAsset>) -> [PHAsset] {
        var out: [PHAsset] = []
        out.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in out.append(asset) }
        return out
    }

    static func allAssets() -> [PHAsset] {
        toArray(fetch(media: .all))
    }

    static func assets(withIDs ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        return toArray(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
    }

    // MARK: Images

    /// Single-callback image request (used by the AI scanner).
    static func image(for asset: PHAsset,
                      targetSize: CGSize,
                      contentMode: PHImageContentMode = .aspectFit,
                      allowNetwork: Bool = true) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat   // guarantees exactly one callback
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowNetwork
        options.isSynchronous = false
        options.version = .current

        return await withCheckedContinuation { continuation in
            imageManager.requestImage(for: asset,
                                      targetSize: targetSize,
                                      contentMode: contentMode,
                                      options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: Video

    /// Returns the video only if it is stored on this iPhone (no iCloud download).
    static func localVideo(for asset: PHAsset) async -> AVAsset? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .fastFormat
        options.version = .current

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    /// Pulls `count` evenly spaced frames out of a video.
    static func frames(from video: AVAsset, count: Int) async -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: video)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let duration = try? await video.load(.duration) else { return [] }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return [] }

        var images: [CGImage] = []
        for i in 0..<count {
            if Task.isCancelled { break }
            let t = seconds * (Double(i) + 0.5) / Double(count)
            if let result = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)) {
                images.append(result.image)
            }
        }
        return images
    }

    static func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    // MARK: Deleting

    /// iOS always shows its own confirmation alert for this. Items go to "Recently Deleted".
    static func delete(ids: [String]) async throws {
        let toDelete = Self.assets(withIDs: ids)
        guard !toDelete.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
