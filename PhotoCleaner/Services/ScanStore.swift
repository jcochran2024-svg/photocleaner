import Foundation

struct ScanRecord: Codable, Equatable {
    var score: Float          // 0...1 from the on-device model
    var isVideo: Bool
    var framesChecked: Int
    var scannedAt: Date
    var reviewedKeep: Bool
}

/// Remembers which items were scanned and their scores.
/// Stored only in the app's private folder, encrypted while the phone is locked,
/// and excluded from iCloud/computer backups.
@MainActor
final class ScanStore: ObservableObject {
    @Published private(set) var records: [String: ScanRecord] = [:]

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("private-scan-results.json")
        load()
    }

    // MARK: Queries

    struct Flagged: Identifiable {
        let id: String
        let record: ScanRecord
    }

    func flagged(threshold: Float, includeKept: Bool) -> [Flagged] {
        records
            .filter { $0.value.score >= threshold && (includeKept || !$0.value.reviewedKeep) }
            .map { Flagged(id: $0.key, record: $0.value) }
            .sorted { $0.record.score > $1.record.score }
    }

    var scannedCount: Int { records.count }

    // MARK: Mutations

    func merge(_ newRecords: [String: ScanRecord]) {
        guard !newRecords.isEmpty else { return }
        records.merge(newRecords) { _, new in new }
    }

    func markKept(_ ids: [String]) {
        for id in ids {
            records[id]?.reviewedKeep = true
        }
        save()
    }

    func unmarkKept(_ ids: [String]) {
        for id in ids {
            records[id]?.reviewedKeep = false
        }
        save()
    }

    func remove(_ ids: [String]) {
        for id in ids {
            records[id] = nil
        }
        save()
    }

    /// Drops results for photos that no longer exist in the library.
    func prune(keeping existing: Set<String>) {
        let stale = records.keys.filter { !existing.contains($0) }
        guard !stale.isEmpty else { return }
        for id in stale { records[id] = nil }
        appLog("Removed \(stale.count) results for photos no longer in the library")
        save()
    }

    func resetAll() {
        records = [:]
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            records = try JSONDecoder().decode([String: ScanRecord].self, from: data)
        } catch {
            appLog("Could not read saved scan results: \(error.localizedDescription)")
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            appLog("Could not save scan results: \(error.localizedDescription)")
        }
    }
}
