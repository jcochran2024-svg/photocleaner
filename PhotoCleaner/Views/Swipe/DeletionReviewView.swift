import SwiftUI
import Photos

/// Everything swiped left. Tap a photo to rescue it; nothing is deleted until you confirm twice.
struct DeletionReviewView: View {
    @EnvironmentObject private var swipeStore: SwipeStore
    @EnvironmentObject private var scanStore: ScanStore
    @EnvironmentObject private var scanEngine: ScanEngine
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var confirm = false
    @State private var working = false
    @State private var resultText: String?

    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 8)]

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                if assets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(resultText ?? "Nothing marked for deletion.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tap a photo to keep it instead.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(assets, id: \.localIdentifier) { asset in
                                    AssetGridCell(asset: asset)
                                        .onTapGesture { rescue(asset) }
                                }
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 100)
                    }
                    .overlay(alignment: .bottom) { deleteBar }
                }
            }
            .navigationTitle("Marked for Deletion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !assets.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Keep all (unmark)", systemImage: "arrow.uturn.backward") {
                                for asset in assets { swipeStore.set(.keep, for: asset.localIdentifier) }
                                reload()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Delete \(assets.count) item(s) from your iPhone?",
                                isPresented: $confirm,
                                titleVisibility: .visible) {
                Button("Delete \(assets.count)", role: .destructive) {
                    Task { await deleteAll() }
                }
            } message: {
                Text("iOS will ask you to confirm once more. They stay in Recently Deleted for 30 days.")
            }
            .onAppear(perform: reload)
        }
    }

    private var deleteBar: some View {
        Button {
            confirm = true
        } label: {
            HStack {
                if working { ProgressView().tint(.white) }
                Text("Delete \(assets.count.grouped) item(s)")
                    .bold()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.delete)
        .disabled(working)
        .padding()
        .background(.ultraThinMaterial)
    }

    private func reload() {
        let ids = swipeStore.markedForDeletion
        let fetched = PhotoLibrary.assets(withIDs: ids)
        // Newest first
        assets = fetched.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        // Forget marks for photos that were already deleted elsewhere.
        let found = Set(fetched.map(\.localIdentifier))
        let missing = ids.filter { !found.contains($0) }
        if !missing.isEmpty { swipeStore.remove(missing) }
    }

    private func rescue(_ asset: PHAsset) {
        Haptics.tap()
        swipeStore.set(.keep, for: asset.localIdentifier)
        withAnimation {
            assets.removeAll { $0.localIdentifier == asset.localIdentifier }
        }
    }

    private func deleteAll() async {
        let ids = assets.map(\.localIdentifier)
        guard !ids.isEmpty else { return }
        working = true
        do {
            try await PhotoLibrary.delete(ids: ids)
            swipeStore.remove(ids)
            scanStore.remove(ids)
            Haptics.success()
            resultText = "Deleted \(ids.count.grouped) item(s).\nYou can still recover them from Recently Deleted for 30 days."
            appLog("Swipe cleaner: deleted \(ids.count) item(s)")
            reload()
            await scanEngine.refreshCounts()
        } catch {
            resultText = nil
            appLog("Swipe cleaner: delete cancelled or failed (\(error.localizedDescription))")
        }
        working = false
    }
}
