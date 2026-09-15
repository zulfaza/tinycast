import Foundation

struct SnippetUsageRecord: Codable, Hashable, Sendable {
    var count: Int
    var lastUsed: Date
}

enum SnippetUsageGroup: String, CaseIterable, Sendable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case older
    case neverUsed

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        case .older: "Older"
        case .neverUsed: "Never Used"
        }
    }

    static func classify(lastUsed: Date?, now: Date, calendar: Calendar) -> Self {
        guard let lastUsed else { return .neverUsed }
        if calendar.isDate(lastUsed, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(lastUsed, inSameDayAs: yesterday)
        {
            return .yesterday
        }
        if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(lastUsed) == true {
            return .thisWeek
        }
        if calendar.dateInterval(of: .month, for: now)?.contains(lastUsed) == true {
            return .thisMonth
        }
        return .older
    }
}

@MainActor
@Observable
final class SnippetUsageStore {
    private let fileURL: URL
    private let now: () -> Date
    private let calendar: Calendar
    private(set) var records: [StoredSnippet.ID: SnippetUsageRecord]
    private var pendingUses: [StoredSnippet.ID: Int] = [:]
    private var isLoaded = false
    private var loadTask: Task<[StoredSnippet.ID: SnippetUsageRecord], Never>?
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    init(fileURL: URL, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.now = now
        self.calendar = calendar
        records = [:]
    }

    isolated deinit {
        loadTask?.cancel()
        writeTask?.cancel()
    }

    func load() async {
        guard !isLoaded else { return }
        if let loadTask {
            let loaded = await loadTask.value
            finishLoading(loaded)
            return
        }
        let fileURL = fileURL
        let task = Task.detached(priority: .utility) {
            Self.readRecords(from: fileURL)
        }
        loadTask = task
        let loaded = await task.value
        finishLoading(loaded)
    }

    func lastUsed(for id: StoredSnippet.ID) -> Date? { records[id]?.lastUsed }

    func group(for id: StoredSnippet.ID) -> SnippetUsageGroup {
        SnippetUsageGroup.classify(lastUsed: lastUsed(for: id), now: now(), calendar: calendar)
    }

    func recordUse(for id: StoredSnippet.ID) {
        let timestamp = now()
        let old = records[id]
        records[id] = SnippetUsageRecord(count: (old?.count ?? 0) + 1, lastUsed: timestamp)
        if !isLoaded { pendingUses[id, default: 0] += 1 }
        persist()
    }

    private func finishLoading(_ loaded: [StoredSnippet.ID: SnippetUsageRecord]) {
        guard !isLoaded else { return }
        loadTask = nil
        var merged = loaded
        for (id, uses) in pendingUses {
            guard let local = records[id] else { continue }
            let persistedCount = loaded[id]?.count ?? 0
            merged[id] = SnippetUsageRecord(
                count: persistedCount + uses, lastUsed: local.lastUsed)
        }
        records = merged
        pendingUses.removeAll()
        isLoaded = true
        if !merged.isEmpty { persist() }
    }

    nonisolated private static func readRecords(
        from fileURL: URL
    ) -> [StoredSnippet.ID: SnippetUsageRecord] {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(
                [StoredSnippet.ID: SnippetUsageRecord].self, from: data)
        else { return [:] }
        return decoded.filter { !$0.key.isEmpty && $0.value.count > 0 }
    }

    private func persist() {
        guard isLoaded else { return }
        let snapshot = records
        let fileURL = fileURL
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            let directory = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
