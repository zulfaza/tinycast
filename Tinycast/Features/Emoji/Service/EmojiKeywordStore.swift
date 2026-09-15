import Foundation

/// Persists user aliases separately from generated CLDR data.
@MainActor
@Observable
final class EmojiKeywordStore {
    private struct Archive: Codable, Sendable {
        let version: Int
        let keywords: [EmojiKeyword]
    }

    static let currentVersion = 1

    private let fileURL: URL
    private(set) var records: [EmojiKeyword]
    private(set) var revision = 0

    init(
        fileURL: URL = AppPaths.applicationSupport()
            .appendingPathComponent("emoji-keywords.json")
    ) {
        self.fileURL = fileURL
        guard let data = try? Data(contentsOf: fileURL),
            let archive = try? JSONDecoder().decode(Archive.self, from: data),
            archive.version == Self.currentVersion
        else {
            records = []
            return
        }
        records = Self.unique(archive.keywords)
    }

    @discardableResult
    func add(glyph: String, keyword: String) -> Bool {
        guard let record = EmojiKeyword(glyph: glyph, value: keyword), !records.contains(record)
        else { return false }
        records = Self.unique(records + [record])
        revision &+= 1
        persist()
        return true
    }

    @discardableResult
    func add(keyword: String, for entry: EmojiEntry) -> Bool {
        add(glyph: entry.glyph, keyword: keyword)
    }

    @discardableResult
    func remove(_ record: EmojiKeyword) -> Bool {
        let next = records.filter { $0 != record }
        guard next.count != records.count else { return false }
        records = next
        revision &+= 1
        persist()
        return true
    }

    /// Replaces all aliases after import; malformed and duplicate records are discarded.
    func replace(_ imported: [EmojiKeyword]) {
        let next = Self.unique(imported)
        guard next != records else { return }
        records = next
        revision &+= 1
        persist()
    }

    private func persist() {
        let archive = Archive(version: Self.currentVersion, keywords: records)
        guard let data = try? JSONEncoder().encode(archive) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func unique(_ values: [EmojiKeyword]) -> [EmojiKeyword] {
        var seen = Set<EmojiKeyword>()
        return values
            .compactMap { EmojiKeyword(glyph: $0.glyph, value: $0.value) }
            .filter { seen.insert($0).inserted }
            .sorted {
                if $0.glyph != $1.glyph { return $0.glyph < $1.glyph }
                return $0.value < $1.value
            }
    }
}
