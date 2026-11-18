import Photos
import UIKit

/// Tracks whether the app has full Photos access.
@MainActor
final class LibraryAccess: ObservableObject {
    @Published private(set) var status: PHAuthorizationStatus = PhotoLibrary.status()

    var hasFullAccess: Bool { status == .authorized }

    func refresh() {
        status = PhotoLibrary.status()
    }

    func request() async {
        if status == .notDetermined {
            status = await PhotoLibrary.requestAccess()
            appLog("Photos permission: \(status.label)")
        } else {
            openSettings()
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

extension PHAuthorizationStatus {
    var label: String {
        switch self {
        case .authorized: return "Full access"
        case .limited: return "Limited access"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }
}
