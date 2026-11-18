import SwiftUI
import Photos

struct HomeView: View {
    @EnvironmentObject private var library: LibraryAccess
    @EnvironmentObject private var scanEngine: ScanEngine
    @EnvironmentObject private var swipeStore: SwipeStore
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if !library.hasFullAccess {
                            permissionCard
                        }

                        NavigationLink {
                            ScannerView()
                        } label: {
                            FeatureCard(title: "AI Privacy Scanner",
                                        subtitle: "Finds sensitive photos & videos with on-device AI. You review everything.",
                                        icon: "eye.trianglebadge.exclamationmark.fill",
                                        gradient: Theme.scanner,
                                        footer: scannerFooter)
                        }
                        .disabled(!library.hasFullAccess)

                        NavigationLink {
                            SwipeCleanerView()
                        } label: {
                            FeatureCard(title: "Swipe Photo Cleaner",
                                        subtitle: "Left to delete, right to keep, up to skip.",
                                        icon: "hand.draw.fill",
                                        gradient: Theme.swipe,
                                        footer: swipeFooter)
                        }
                        .disabled(!library.hasFullAccess)

                        privacyNote
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                if library.status == .notDetermined {
                    await library.request()
                }
                await scanEngine.refreshCounts()
            }
            .onChange(of: library.status) { _, _ in
                Task { await scanEngine.refreshCounts() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PhotoCleaner")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
            if let count = scanEngine.libraryCount {
                Text("\(count.grouped) photos & videos in your library")
                    .foregroundStyle(.secondary)
            } else {
                Text("Clean up your camera roll privately")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var scannerFooter: String {
        if scanEngine.isRunning {
            return "Scanning… \(Int(scanEngine.progress * 100))%"
        }
        if let unscanned = scanEngine.unscannedCount {
            return unscanned == 0 ? "Everything scanned" : "\(unscanned.grouped) not scanned yet"
        }
        return "Tap to start"
    }

    private var swipeFooter: String {
        let marked = swipeStore.markedForDeletion.count
        return marked == 0 ? "Nothing marked yet" : "\(marked.grouped) marked for deletion"
    }

    private var permissionCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Full photo access needed", systemImage: "lock.shield.fill")
                    .font(.headline)
                Text(library.status == .limited
                     ? "You gave access to only some photos. Choose \"Allow Full Access\" in Settings so the whole camera roll can be cleaned."
                     : "PhotoCleaner needs access to your library. Everything is processed on this iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await library.request() }
                } label: {
                    Text(library.status == .notDetermined ? "Allow Access" : "Open Settings")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "iphone.gen3")
                .foregroundStyle(Theme.accent)
            Text("100% on-device. This app contains no networking code and never uploads your photos. Deleting always asks you first.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }
}

struct FeatureCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: LinearGradient
    let footer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 8)
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.leading)
            HStack {
                Text(footer)
                    .font(.footnote.bold())
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
            }
            .foregroundStyle(.white)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
        .background(gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }
}
