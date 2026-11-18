import Photos
import SwiftUI

enum SwipeAction {
    case keep
    case delete
    case skip
}

enum DateRangeOption: String, CaseIterable, Identifiable {
    case all, last30Days, last12Months, thisYear, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All time"
        case .last30Days: return "Last 30 days"
        case .last12Months: return "Last 12 months"
        case .thisYear: return "This year"
        case .custom: return "Custom range"
        }
    }
}

struct SwipeFilter: Equatable {
    var range: DateRangeOption = .all
    var customFrom: Date = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    var customTo: Date = Date()
    var media: MediaFilter = .all
    var hideReviewed = true
    var oldestFirst = false

    var dates: (from: Date?, to: Date?) {
        let cal = Calendar.current
        let now = Date()
        switch range {
        case .all:
            return (nil, nil)
        case .last30Days:
            return (cal.date(byAdding: .day, value: -30, to: now), nil)
        case .last12Months:
            return (cal.date(byAdding: .month, value: -12, to: now), nil)
        case .thisYear:
            return (cal.date(from: cal.dateComponents([.year], from: now)), nil)
        case .custom:
            let start = cal.startOfDay(for: min(customFrom, customTo))
            let endDay = cal.startOfDay(for: max(customFrom, customTo))
            let end = cal.date(byAdding: .day, value: 1, to: endDay)?.addingTimeInterval(-1)
            return (start, end)
        }
    }

    var summary: String {
        var parts: [String] = [range == .custom ? "Custom dates" : range.title]
        if media != .all { parts.append(media.title) }
        if oldestFirst { parts.append("Oldest first") }
        return parts.joined(separator: " · ")
    }
}

/// One swipe session: the deck of photos plus undo history.
@MainActor
final class SwipeSession: ObservableObject {
    struct HistoryEntry {
        let id: String
        let previous: SwipeDecision?
        let action: SwipeAction
    }

    @Published private(set) var deck: [PHAsset] = []
    @Published private(set) var index = 0
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var sessionKept = 0
    @Published private(set) var sessionDeleted = 0
    @Published private(set) var sessionSkipped = 0
    @Published var filter = SwipeFilter()

    private let prefetchSize = CGSize(width: 1200, height: 1200)
    private var cachedIDs: [PHAsset] = []

    var current: PHAsset? { index < deck.count ? deck[index] : nil }
    var next: PHAsset? { index + 1 < deck.count ? deck[index + 1] : nil }
    var isFinished: Bool { !isLoading && index >= deck.count }
    var progress: Double { deck.isEmpty ? 0 : Double(index) / Double(deck.count) }

    func load(store: SwipeStore) async {
        isLoading = true
        let filter = self.filter
        let dates = filter.dates
        let all: [PHAsset] = await Task.detached(priority: .userInitiated) {
            PhotoLibrary.toArray(PhotoLibrary.fetch(media: filter.media,
                                                    from: dates.from,
                                                    to: dates.to,
                                                    oldestFirst: filter.oldestFirst))
        }.value

        if filter.range == .all && filter.media == .all {
            store.prune(keeping: Set(all.map(\.localIdentifier)))
        }
        let decided = store.decisions
        deck = filter.hideReviewed ? all.filter { decided[$0.localIdentifier] == nil } : all
        index = 0
        history = []
        sessionKept = 0
        sessionDeleted = 0
        sessionSkipped = 0
        isLoading = false
        updatePrefetch()
        appLog("Swipe deck loaded: \(deck.count) items (\(filter.summary))")
    }

    func apply(_ action: SwipeAction, store: SwipeStore) {
        guard let asset = current else { return }
        let id = asset.localIdentifier
        history.append(HistoryEntry(id: id, previous: store.decision(for: id), action: action))
        if history.count > 200 { history.removeFirst() }

        switch action {
        case .keep:
            store.set(.keep, for: id)
            sessionKept += 1
        case .delete:
            store.set(.delete, for: id)
            sessionDeleted += 1
        case .skip:
            sessionSkipped += 1
        }
        index += 1
        updatePrefetch()
    }

    func undo(store: SwipeStore) {
        guard let last = history.popLast(), index > 0 else { return }
        index -= 1
        // The deck item at `index` is the one we are undoing.
        if deck[index].localIdentifier == last.id {
            store.set(last.previous, for: last.id)
        }
        switch last.action {
        case .keep: sessionKept = max(0, sessionKept - 1)
        case .delete: sessionDeleted = max(0, sessionDeleted - 1)
        case .skip: sessionSkipped = max(0, sessionSkipped - 1)
        }
        updatePrefetch()
    }

    /// Keeps only the next few full-size images warm so thousands of photos never sit in memory.
    private func updatePrefetch() {
        let upcoming = Array(deck[min(index, deck.count)..<min(index + 4, deck.count)])
        let stale = cachedIDs.filter { old in !upcoming.contains(where: { $0.localIdentifier == old.localIdentifier }) }
        if !stale.isEmpty {
            PhotoLibrary.imageManager.stopCachingImages(for: stale,
                                                        targetSize: prefetchSize,
                                                        contentMode: .aspectFit,
                                                        options: nil)
        }
        let fresh = upcoming.filter { new in !cachedIDs.contains(where: { $0.localIdentifier == new.localIdentifier }) }
        if !fresh.isEmpty {
            PhotoLibrary.imageManager.startCachingImages(for: fresh,
                                                         targetSize: prefetchSize,
                                                         contentMode: .aspectFit,
                                                         options: nil)
        }
        cachedIDs = upcoming
    }
}
