import Foundation
import os

/// In-app log so problems can be diagnosed without a Mac/debugger.
/// Never logs image content — only counts, IDs-free status messages and errors.
@MainActor
final class AppLog: ObservableObject {
    static let shared = AppLog()

    @Published private(set) var lines: [String] = []

    private let logger = Logger(subsystem: "com.johnny.photocleaner", category: "app")
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm:ss"
        return f
    }()

    func add(_ message: String) {
        logger.log("\(message, privacy: .public)")
        lines.append("\(formatter.string(from: Date()))  \(message)")
        if lines.count > 600 {
            lines.removeFirst(lines.count - 600)
        }
    }

    func clear() {
        lines.removeAll()
    }
}

/// Thread-safe logging helper callable from anywhere.
func appLog(_ message: String) {
    Task { @MainActor in
        AppLog.shared.add(message)
    }
}
