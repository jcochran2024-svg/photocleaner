import Photos
import SwiftUI

/// Loads one PhotoKit image for display and cancels the request when the view goes away,
/// so scrolling through thousands of items never piles up memory.
@MainActor
final class AssetImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var isInCloudOnly = false

    private var requestID: PHImageRequestID?
    private var currentID: String?

    func load(_ asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode) {
        if currentID == asset.localIdentifier, image != nil { return }
        cancel()
        image = nil
        let id = asset.localIdentifier
        currentID = id

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic    // quick preview first, sharp version after
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.version = .current

        requestID = PhotoLibrary.imageManager.requestImage(for: asset,
                                                           targetSize: targetSize,
                                                           contentMode: contentMode,
                                                           options: options) { [weak self] result, info in
            let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
            Task { @MainActor in
                guard let self, self.currentID == id else { return }
                if let result {
                    self.image = result
                }
                self.isInCloudOnly = inCloud && result == nil
            }
        }
    }

    func cancel() {
        if let requestID {
            PhotoLibrary.imageManager.cancelImageRequest(requestID)
        }
        requestID = nil
        currentID = nil
    }
}

struct AssetImage: View {
    let asset: PHAsset
    var fill: Bool = true
    var targetSize: CGSize = CGSize(width: 300, height: 300)

    @StateObject private var loader = AssetImageLoader()

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Color.white.opacity(0.05)
                ProgressView()
                    .tint(.white.opacity(0.5))
            }
        }
        .onAppear { start() }
        .onChange(of: asset.localIdentifier) { _, _ in start() }
        .onDisappear { loader.cancel() }
    }

    private func start() {
        loader.load(asset, targetSize: targetSize, contentMode: fill ? .aspectFill : .aspectFit)
    }
}

/// Square grid cell with optional blur and badges.
struct AssetGridCell: View {
    let asset: PHAsset
    var blurred: Bool = false
    var selected: Bool = false
    var badge: String? = nil
    var badgeColor: Color = .black.opacity(0.6)

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AssetImage(asset: asset, fill: true, targetSize: CGSize(width: 300, height: 300))
                    .blur(radius: blurred ? 18 : 0, opaque: true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    Label(Self.duration(asset.duration), systemImage: "video.fill")
                        .font(.caption2.bold())
                        .padding(4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.caption2.monospacedDigit().bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(badgeColor, in: Capsule())
                        .padding(5)
                }
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.accent, lineWidth: 3)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                }
            }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
