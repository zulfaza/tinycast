import Foundation

struct Snippet: Sendable, Hashable {
    var name: String
    var text: String
    var keyword: String?
    var tags: [String]
    var isEnabled: Bool
    var showsConfirmation: Bool

    init(
        name: String,
        text: String,
        keyword: String? = nil,
        tags: [String] = [],
        isEnabled: Bool = true,
        showsConfirmation: Bool = false
    ) {
        self.name = name
        self.text = text
        self.keyword = keyword
        self.tags = Self.normalizedTags(tags)
        self.isEnabled = isEnabled
        self.showsConfirmation = showsConfirmation
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { rawTag in
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { return nil }
            let key = tag.localizedLowercase
            guard seen.insert(key).inserted else { return nil }
            return tag
        }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

enum SnippetExpansionOutput: String, CaseIterable, Sendable {
    case markdown
    case plainText

    var title: String { self == .markdown ? "Rich Markdown" : "Plain text" }
}

enum SnippetExpansionTriggerMode: String, CaseIterable, Sendable {
    case immediate
    case delimiter
}

enum SnippetInjectionDelay: Int, CaseIterable, Identifiable, Sendable {
    case none = 0
    case short = 50
    case medium = 100
    case long = 250
    case extraLong = 500

    var id: Int { rawValue }
    var title: String { rawValue == 0 ? "None" : "\(rawValue) ms" }
    var duration: Duration { .milliseconds(rawValue) }
}

struct SnippetExpansionTrigger: Sendable, Equatable {
    var mode: SnippetExpansionTriggerMode
    var delimiter: String
    var retainsDelimiter: Bool

    static let `default` = Self(mode: .immediate, delimiter: "whitespace", retainsDelimiter: true)

    init(
        mode: SnippetExpansionTriggerMode = .immediate,
        delimiter: String = "whitespace",
        retainsDelimiter: Bool = true
    ) {
        self.mode = mode
        self.delimiter = delimiter.isEmpty ? "whitespace" : delimiter
        self.retainsDelimiter = retainsDelimiter
    }
}

/// Fingerprint of a snippet file's bytes, detecting an external edit before a save or delete.
struct SnippetSourceRevision: Sendable, Hashable {
    private let value: String

    init(content: String) {
        var hash: UInt64 = 14_695_981_039_346_656_037
        var byteCount = 0
        for byte in content.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
            byteCount += 1
        }
        value = "\(byteCount):\(String(hash, radix: 16))"
    }
}

struct StoredSnippet: Identifiable, Sendable, Hashable {
    let fileURL: URL
    var snippet: Snippet
    let sourceRevision: SnippetSourceRevision

    var id: String { fileURL.standardizedFileURL.path }
}
