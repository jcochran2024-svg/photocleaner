import Photos
import UIKit

/// Scans the library with the on-device model. Never deletes anything.
@MainActor
final class ScanEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case scanning
        case finished
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var total = 0
    @Published private(set) var done = 0
    @Published private(set) var failedCount = 0
    @Published private(set) var unscannedCount: Int?
    @Published private(set) var libraryCount: Int?

    let store: ScanStore
    private var task: Task<Void, Never>?
    private var buffer: [String: ScanRecord] = [:]

    /// How many items are analysed at the same time.
    private let parallelism = 3
    /// Frames sampled per video.
    private let framesPerVideo = 6

    init(store: ScanStore) {
        self.store = store
    }

    var isRunning: Bool {
        phase == .preparing || phase == .scanning
    }

    var progress: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    // MARK: Counting

    func refreshCounts() async {
        guard PhotoLibrary.status() == .authorized else { return }
        let ids: [String] = await Task.detached(priority: .utility) {
            PhotoLibrary.allAssets().map(\.localIdentifier)
        }.value
        libraryCount = ids.count
        unscannedCount = ids.filter { store.records[$0] == nil }.count
    }

    // MARK: Scanning

    /// Scans everything not scanned yet. `rescanAll` throws away old results first.
    func start(rescanAll: Bool = false) {
        guard !isRunning else { return }
        guard let classifier = NSFWClassifier.shared else {
            phase = .failed("The AI model could not be loaded on this device.")
            return
        }
        if rescanAll {
            store.resetAll()
        }

        phase = .preparing
        done = 0
        total = 0
        failedCount = 0
        UIApplication.shared.isIdleTimerDisabled = true
        appLog(rescanAll ? "Full rescan started" : "Scan started")

        task = Task { [weak self] in
            let assets: [PHAsset] = await Task.detached(priority: .userInitiated) {
                PhotoLibrary.allAssets()
            }.value
            guard let self else { return }

            self.store.prune(keeping: Set(assets.map(\.localIdentifier)))
            let known = Set(self.store.records.keys)
            let todo = assets.filter { !known.contains($0.localIdentifier) }

            self.libraryCount = assets.count
            self.total = todo.count
            self.phase = .scanning
            appLog("Library: \(assets.count) items, \(todo.count) to scan")

            let started = Date()
            var index = 0
            var sinceSave = 0

            while index < todo.count {
                if Task.isCancelled { break }
                let slice = Array(todo[index..<min(index + self.parallelism, todo.count)])
                index += slice.count

                let frames = self.framesPerVideo
                let results = await withTaskGroup(of: (String, ScanRecord?).self) { group -> [(String, ScanRecord?)] in
                    for asset in slice {
                        group.addTask {
                            await ScanEngine.analyze(asset, classifier: classifier, framesPerVideo: frames)
                        }
                    }
                    var collected: [(String, ScanRecord?)] = []
                    for await result in group {
                        collected.append(result)
                    }
                    return collected
                }

                for (id, record) in results {
                    if let record {
                        self.buffer[id] = record
                    } else {
                        self.failedCount += 1
                    }
                }
                self.done += results.count
                sinceSave += results.count

                if self.buffer.count >= 24 {
                    self.flush()
                }
                if sinceSave >= 300 {
                    sinceSave = 0
                    self.store.save()
                }
            }

            self.flush()
            self.store.save()
            UIApplication.shared.isIdleTimerDisabled = false
            let seconds = Int(Date().timeIntervalSince(started))
            if Task.isCancelled {
                self.phase = .idle
                appLog("Scan stopped after \(self.done) items (\(seconds)s)")
            } else {
                self.phase = .finished
                appLog("Scan finished: \(self.done) items in \(seconds)s, \(self.failedCount) could not be read")
            }
            await self.refreshCounts()
        }
    }

    func stop() {
        task?.cancel()
    }

    /// Moves buffered results into the store (called often + when app backgrounds).
    func flush() {
        guard !buffer.isEmpty else { return }
        store.merge(buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    // MARK: Analysis (runs off the main thread)

    nonisolated static func analyze(_ asset: PHAsset,
                                    classifier: NSFWClassifier,
                                    framesPerVideo: Int) async -> (String, ScanRecord?) {
        let id = asset.localIdentifier
        let isVideo = asset.mediaType == .video
        var best: Float = -1
        var checked = 0

        if isVideo {
            var frames: [CGImage] = []
            if let video = await PhotoLibrary.localVideo(for: asset) {
                frames = await PhotoLibrary.frames(from: video, count: framesPerVideo)
            }
            if frames.isEmpty,
               let poster = await PhotoLibrary.image(for: asset, targetSize: CGSize(width: 480, height: 480)),
               let cg = poster.cgImage {
                // Video lives only in iCloud: fall back to its preview frame (small download).
                frames = [cg]
            }
            for frame in frames {
                if let score = try? classifier.score(frame) {
                    best = max(best, score)
                    checked += 1
                }
            }
        } else {
            if let image = await PhotoLibrary.image(for: asset, targetSize: CGSize(width: 480, height: 480)),
               let cg = image.cgImage {
                let orientation = CGImagePropertyOrientation(image.imageOrientation)
                if let score = try? classifier.score(cg, orientation: orientation) {
                    best = score
                    checked = 1
                }
            }
        }

        guard best >= 0 else { return (id, nil) }
        return (id, ScanRecord(score: best,
                               isVideo: isVideo,
                               framesChecked: checked,
                               scannedAt: Date(),
                               reviewedKeep: false))
    }
}
