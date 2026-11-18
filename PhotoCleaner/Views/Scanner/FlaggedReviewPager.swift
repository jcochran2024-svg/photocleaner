import SwiftUI
import Photos
import AVKit

/// Full-screen, one-at-a-time review of flagged items with Keep / Delete.
struct FlaggedReviewPager: View {
    let blurred: Bool
    let onKeep: (String) -> Void
    let onDelete: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var items: [FlaggedItem]
    @State private var currentID: String
    @State private var revealed = Set<String>()
    @State private var working = false

    init(items: [FlaggedItem],
         startID: String,
         blurred: Bool,
         onKeep: @escaping (String) -> Void,
         onDelete: @escaping (String) async -> Bool) {
        self.blurred = blurred
        self.onKeep = onKeep
        self.onDelete = onDelete
        _items = State(initialValue: items)
        _currentID = State(initialValue: startID)
    }

    private var currentIndex: Int {
        items.firstIndex(where: { $0.id == currentID }) ?? 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(items) { item in
                    page(item)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Page

    @ViewBuilder
    private func page(_ item: FlaggedItem) -> some View {
        let isHidden = blurred && !revealed.contains(item.id)
        ZStack {
            if item.asset.mediaType == .video && !isHidden {
                FlaggedVideoView(asset: item.asset)
            } else {
                AssetImage(asset: item.asset, fill: false, targetSize: CGSize(width: 1400, height: 1400))
                    .blur(radius: isHidden ? 40 : 0, opaque: true)
                    .clipped()
            }
            if isHidden {
                Button {
                    revealed.insert(item.id)
                } label: {
                    Label("Tap to reveal", systemImage: "eye")
                        .font(.headline)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 90)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            if let item = items.first(where: { $0.id == currentID }) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(item.record.score * 100))% confidence")
                        .font(.subheadline.bold())
                    Text(detailLine(item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .foregroundStyle(.white)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Text("\(min(currentIndex + 1, items.count)) of \(items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button {
                    act(delete: false)
                } label: {
                    Label("Keep", systemImage: "checkmark")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(Theme.keep)

                Button {
                    act(delete: true)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.delete)
            }
            .disabled(working || items.isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: Actions

    private func act(delete: Bool) {
        let id = currentID
        guard items.contains(where: { $0.id == id }) else { return }
        working = true
        Task {
            var done = true
            if delete {
                done = await onDelete(id)
            } else {
                onKeep(id)
            }
            if done {
                removeAndAdvance(id)
            }
            working = false
        }
    }

    private func removeAndAdvance(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        if items.isEmpty {
            dismiss()
            return
        }
        currentID = items[min(index, items.count - 1)].id
    }

    private func detailLine(_ item: FlaggedItem) -> String {
        var parts: [String] = []
        if let date = item.asset.creationDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if item.record.isVideo {
            parts.append("Video · \(item.record.framesChecked) frame(s) checked")
        }
        return parts.joined(separator: " · ")
    }
}

/// Plays a flagged video on demand.
struct FlaggedVideoView: View {
    let asset: PHAsset
    @State private var player: AVPlayer?
    @State private var loading = false

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .onDisappear { player.pause() }
            } else {
                AssetImage(asset: asset, fill: false, targetSize: CGSize(width: 1200, height: 1200))
                Button {
                    Task { await load() }
                } label: {
                    Group {
                        if loading {
                            ProgressView()
                        } else {
                            Image(systemName: "play.fill")
                                .font(.title)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true
        if let item = await PhotoLibrary.playerItem(for: asset) {
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer
            newPlayer.play()
        }
        loading = false
    }
}
