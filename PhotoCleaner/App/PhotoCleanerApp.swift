import SwiftUI

@main
struct PhotoCleanerApp: App {
    @StateObject private var scanStore: ScanStore
    @StateObject private var scanEngine: ScanEngine
    @StateObject private var swipeStore: SwipeStore
    @StateObject private var appLock = AppLock()
    @StateObject private var library = LibraryAccess()

    init() {
        let store = ScanStore()
        _scanStore = StateObject(wrappedValue: store)
        _scanEngine = StateObject(wrappedValue: ScanEngine(store: store))
        _swipeStore = StateObject(wrappedValue: SwipeStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(scanStore)
                .environmentObject(scanEngine)
                .environmentObject(swipeStore)
                .environmentObject(appLock)
                .environmentObject(library)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

/// Watches app lifecycle so data is saved and the private scanner re-locks.
struct RootView: View {
    @EnvironmentObject private var scanStore: ScanStore
    @EnvironmentObject private var scanEngine: ScanEngine
    @EnvironmentObject private var swipeStore: SwipeStore
    @EnvironmentObject private var appLock: AppLock
    @EnvironmentObject private var library: LibraryAccess
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HomeView()
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    scanEngine.flush()
                    scanStore.save()
                    swipeStore.saveNow()
                    appLock.lock()
                case .active:
                    library.refresh()
                default:
                    break
                }
            }
    }
}
