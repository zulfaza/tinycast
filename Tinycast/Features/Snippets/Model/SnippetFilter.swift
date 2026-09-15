import Foundation

struct SnippetFilter: Sendable {
    let textTerms: [String]
    let tags: [String]

    init(query: String) {
        var textTerms: [String] = []
        var tags: [String] = []
        for term in query.split(whereSeparator: { $0.isWhitespace }) {
            let value = String(term)
            if value.first == "#", value.count > 1 {
                tags.append(String(value.dropFirst()).localizedLowercase)
            } else {
                textTerms.append(value.localizedLowercase)
            }
        }
        self.textTerms = textTerms
        self.tags = tags
    }

    func matches(_ record: StoredSnippet) -> Bool {
        let tagValues = Set(record.snippet.tags.map(\.localizedLowercase))
        guard tags.allSatisfy(tagValues.contains) else { return false }
        guard !textTerms.isEmpty else { return true }
        let searchable = [record.snippet.name, record.snippet.keyword ?? ""]
            .joined(separator: " ")
            .localizedLowercase
        return textTerms.allSatisfy { searchable.localizedCaseInsensitiveContains($0) }
    }
}
