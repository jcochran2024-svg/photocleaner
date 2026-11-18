import LocalAuthentication
import SwiftUI

/// Face ID / passcode lock for the private scanner results.
@MainActor
final class AppLock: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published var lastError: String?
    var requireFaceID: Bool {
        get { UserDefaults.standard.object(forKey: "requireFaceID") as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "requireFaceID")
        }
    }

    func lock() {
        isUnlocked = false
    }

    func unlock() async {
        guard requireFaceID else {
            isUnlocked = true
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on this iPhone, so there is nothing to lock with.
            lastError = "Set a passcode on your iPhone to protect scanner results."
            isUnlocked = true
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: "Unlock your private scan results")
            isUnlocked = ok
            lastError = nil
        } catch {
            isUnlocked = false
            lastError = "Locked. Tap Unlock to try again."
        }
    }
}
