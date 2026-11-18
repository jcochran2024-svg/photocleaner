import Foundation

enum SwipeDecision: String, Codable {
    case keep
    case delete
}

/// Remembers Keep / Delete decisions from the swipe cleaner between launches.
@MainActor
final class SwipeStore: ObservableObject {
    @Published private(set) var decisions: [String: SwipeDecision] = [:]

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("swipe-decisions.json")
        load()
    }

    var markedForDeletion: [String] {
        decisions.compactMap { $0.value == .delete ? $0.key : nil }
    }

    var keptCount: Int {
        decisions.values.filter { $0 == .keep }.count
    }

    func decision(for id: String) -> SwipeDecision? {
        decisions[id]
    }

    func set(_ decision: SwipeDecision?, for id: String) {
        decisions[id] = decision
        scheduleSave()
    }

    func remove(_ ids: [String]) {
        for id in ids { decisions[id] = nil }
        saveNow()
    }

    func prune(keeping existing: Set<String>) {
        let stale = decisions.keys.filter { !existing.contains($0) }
        guard !stale.isEmpty else { return }
        for id in stale { decisions[id] = nil }
        saveNow()
    }

    func resetAll() {
        decisions = [:]
        saveNow()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        decisions = (try? JSONDecoder().decode([String: SwipeDecision].self, from: data)) ?? [:]
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            let data = try JSONEncoder().encode(decisions)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            appLog("Could not save swipe decisions: \(error.localizedDescription)")
        }
    }
}
