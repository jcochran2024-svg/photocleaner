import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var appLock: AppLock
    @EnvironmentObject private var scanStore: ScanStore
    @EnvironmentObject private var scanEngine: ScanEngine
    @EnvironmentObject private var swipeStore: SwipeStore
    @EnvironmentObject private var library: LibraryAccess
    @ObservedObject private var log = AppLog.shared
    @Environment(\.dismiss) private var dismiss

    @State private var confirmClearScan = false
    @State private var confirmClearSwipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    Toggle("Require Face ID for scanner", isOn: Binding(
                        get: { appLock.requireFaceID },
                        set: { appLock.requireFaceID = $0 }
                    ))
                    LabeledContent("Photos access", value: library.status.label)
                    Button("Change Photos access in Settings") { library.openSettings() }
                }

                Section {
                    LabeledContent("Scanned items", value: scanStore.scannedCount.grouped)
                    LabeledContent("Swipe decisions", value: swipeStore.decisions.count.grouped)
                    Button("Clear scanner results", role: .destructive) { confirmClearScan = true }
                        .disabled(scanEngine.isRunning)
                    Button("Clear swipe history", role: .destructive) { confirmClearSwipe = true }
                } header: {
                    Text("Saved data")
                } footer: {
                    Text("Saved only inside this app on this iPhone, encrypted while locked and excluded from backups. Clearing never deletes photos.")
                }

                Section {
                    NavigationLink("Diagnostic log (\(log.lines.count))") {
                        LogView()
                    }
                } footer: {
                    Text("If something goes wrong, copy this log and paste it to whoever is helping you build the app.")
                }

                Section("About") {
                    Text("AI model: NSFW.mlmodel by LOVOO GmbH (BSD license), run with Core ML + Vision entirely on this iPhone. Results can be wrong — always review before deleting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Clear all scanner results?", isPresented: $confirmClearScan, titleVisibility: .visible) {
                Button("Clear results", role: .destructive) {
                    scanStore.resetAll()
                    Task { await scanEngine.refreshCounts() }
                }
            }
            .confirmationDialog("Clear all swipe decisions?", isPresented: $confirmClearSwipe, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { swipeStore.resetAll() }
            } message: {
                Text("This also clears your list of photos marked for deletion.")
            }
        }
    }
}

struct LogView: View {
    @ObservedObject private var log = AppLog.shared

    var body: some View {
        List {
            if log.lines.isEmpty {
                Text("No log entries yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(log.lines.enumerated().reversed()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Log")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Copy all", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = log.lines.joined(separator: "\n")
                    }
                    Button("Clear", systemImage: "trash", role: .destructive) {
                        log.clear()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
