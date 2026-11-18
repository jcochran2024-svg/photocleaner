import SwiftUI
import Photos

struct FlaggedItem: Identifiable {
    let id: String
    let record: ScanRecord
    let asset: PHAsset
}

/// Entry point: shows a Face ID lock before any results are visible.
struct ScannerView: View {
    @EnvironmentObject private var appLock: AppLock

    var body: some View {
        ZStack {
            ScreenBackground()
            if appLock.isUnlocked {
                ScannerContent()
            } else {
                LockedView()
            }
        }
        .navigationTitle("AI Privacy Scanner")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LockedView: View {
    @EnvironmentObject private var appLock: AppLock

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "faceid")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            Text("Private results are locked")
                .font(.title3.bold())
            if let error = appLock.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await appLock.unlock() }
            } label: {
                Text("Unlock").bold().frame(width: 180)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .task { await appLock.unlock() }
    }
}

struct ScannerContent: View {
    @EnvironmentObject private var scanStore: ScanStore
    @EnvironmentObject private var scanEngine: ScanEngine
    @EnvironmentObject private var swipeStore: SwipeStore

    @AppStorage("nsfwThreshold") private var threshold: Double = 0.6
    @AppStorage("blurFlagged") private var blurFlagged = true
    @State private var showKept = false

    @State private var items: [FlaggedItem] = []
    @State private var isSelecting = false
    @State private var selection = Set<String>()
    @State private var detailItem: FlaggedItem?
    @State private var confirmDelete = false
    @State private var confirmRescan = false
    @State private var message: String?

    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusPanel
                controlsPanel

                HStack {
                    Text("Flagged (\(items.count.grouped))")
                        .font(.headline)
                    Spacer()
                    if !items.isEmpty {
                        Button(isSelecting ? "Done" : "Select") {
                            isSelecting.toggle()
                            selection.removeAll()
                        }
                        .font(.subheadline.bold())
                    }
                }
                .padding(.top, 4)

                if items.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(items) { item in
                            AssetGridCell(asset: item.asset,
                                          blurred: blurFlagged,
                                          selected: selection.contains(item.id),
                                          badge: "\(Int(item.record.score * 100))%",
                                          badgeColor: badgeColor(item.record.score))
                                .opacity(item.record.reviewedKeep ? 0.45 : 1)
                                .onTapGesture { tapped(item) }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, isSelecting ? 90 : 20)
        }
        .overlay(alignment: .bottom) {
            if isSelecting {
                selectionBar
            }
        }
        .overlay(alignment: .top) {
            if let message {
                Text(message)
                    .font(.footnote.bold())
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { self.message = nil }
            }
        }
        .animation(.spring(duration: 0.3), value: message)
        .onAppear(perform: rebuild)
        .onReceive(scanStore.$records) { _ in rebuild() }
        .onChange(of: threshold) { _, _ in rebuild() }
        .onChange(of: showKept) { _, _ in rebuild() }
        .fullScreenCover(item: $detailItem) { start in
            FlaggedReviewPager(items: items,
                               startID: start.id,
                               blurred: blurFlagged,
                               onKeep: { id in keep([id]) },
                               onDelete: { id in await delete([id]) })
        }
        .confirmationDialog("Delete \(selection.count) item(s)?",
                            isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete \(selection.count)", role: .destructive) {
                let ids = Array(selection)
                Task { await delete(ids) }
            }
        } message: {
            Text("iOS will ask you to confirm once more. Deleted items stay in Recently Deleted for 30 days.")
        }
        .confirmationDialog("Rescan everything?", isPresented: $confirmRescan, titleVisibility: .visible) {
            Button("Rescan entire library", role: .destructive) {
                scanEngine.start(rescanAll: true)
            }
        } message: {
            Text("Clears all saved results (including items you marked Keep) and scans every item again.")
        }
    }

    // MARK: Panels

    private var statusPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                switch scanEngine.phase {
                case .preparing:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading your library…")
                    }
                case .scanning:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Scanning on-device")
                                .font(.headline)
                            Spacer()
                            Text("\(scanEngine.done.grouped) / \(scanEngine.total.grouped)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: scanEngine.progress)
                        Text("Keep the app open. Progress is saved if you leave.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            scanEngine.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                default:
                    idleStatus
                }
            }
        }
    }

    @ViewBuilder
    private var idleStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .failed(let reason) = scanEngine.phase {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.delete)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(scanStore.scannedCount.grouped) scanned")
                        .font(.headline)
                    if let unscanned = scanEngine.unscannedCount {
                        Text(unscanned == 0 ? "Library is fully scanned" : "\(unscanned.grouped) new items to scan")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Rescan entire library", systemImage: "arrow.clockwise") {
                        confirmRescan = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                }
            }
            Button {
                Haptics.tap()
                scanEngine.start()
            } label: {
                Label(scanStore.scannedCount == 0 ? "Scan my library" : "Scan new items",
                      systemImage: "sparkle.magnifyingglass")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(scanEngine.unscannedCount == 0)
            if scanEngine.failedCount > 0 {
                Text("\(scanEngine.failedCount) item(s) couldn't be read (often iCloud items while offline). They'll be retried next scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controlsPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Sensitivity")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("flag at ≥ \(Int(threshold * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $threshold, in: 0.3...0.99, step: 0.01)
                Text("Lower = catches more but more false alarms. Changing this never needs a rescan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Toggle("Blur thumbnails", isOn: $blurFlagged)
                Toggle("Show items I chose to keep", isOn: $showKept)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: scanStore.scannedCount == 0 ? "sparkle.magnifyingglass" : "checkmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(scanStore.scannedCount == 0 ? "Run a scan to see results here." : "Nothing flagged at this sensitivity.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Button {
                keep(Array(selection))
                selection.removeAll()
            } label: {
                Label("Keep \(selection.count)", systemImage: "checkmark")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(Theme.keep)

            Button {
                confirmDelete = true
            } label: {
                Label("Delete \(selection.count)", systemImage: "trash")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.delete)
        }
        .disabled(selection.isEmpty)
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: Actions

    private func tapped(_ item: FlaggedItem) {
        if isSelecting {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
            Haptics.tap()
        } else {
            detailItem = item
        }
    }

    private func badgeColor(_ score: Float) -> Color {
        if score >= 0.9 { return Theme.delete.opacity(0.9) }
        if score >= 0.75 { return Color.orange.opacity(0.9) }
        return Color.black.opacity(0.6)
    }

    private func rebuild() {
        let flagged = scanStore.flagged(threshold: Float(threshold), includeKept: showKept)
        let assets = PhotoLibrary.assets(withIDs: flagged.map(\.id))
        let byID = Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        items = flagged.compactMap { entry in
            byID[entry.id].map { FlaggedItem(id: entry.id, record: entry.record, asset: $0) }
        }
        selection = selection.filter { id in items.contains(where: { $0.id == id }) }
    }

    private func keep(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        scanStore.markKept(ids)
        Haptics.success()
        show("Kept \(ids.count). Hidden from this list.")
    }

    @discardableResult
    private func delete(_ ids: [String]) async -> Bool {
        guard !ids.isEmpty else { return false }
        do {
            try await PhotoLibrary.delete(ids: ids)
            scanStore.remove(ids)
            swipeStore.remove(ids)
            selection.subtract(ids)
            Haptics.success()
            show("Deleted \(ids.count). Recoverable in Recently Deleted for 30 days.")
            appLog("Scanner: deleted \(ids.count) item(s)")
            await scanEngine.refreshCounts()
            return true
        } catch {
            show("Nothing was deleted.")
            appLog("Scanner: delete cancelled or failed (\(error.localizedDescription))")
            return false
        }
    }

    private func show(_ text: String) {
        message = text
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if message == text { message = nil }
        }
    }
}
