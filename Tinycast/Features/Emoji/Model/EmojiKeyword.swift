import Foundation

/// One user-provided search word for a catalog glyph.
struct EmojiKeyword: Codable, Hashable, Identifiable, Sendable {
    let glyph: String
    let value: String

    var id: String { "\(glyph)\u{1F}\(value)" }

    init?(glyph: String, value: String) {
        let trimmedGlyph = glyph.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = Self.normalize(value)
        guard !trimmedGlyph.isEmpty, !normalizedValue.isEmpty,
            normalizedValue.count <= Self.maximumLength,
            !normalizedValue.contains("|"), !normalizedValue.contains(",")
        else { return nil }
        self.glyph = trimmedGlyph
        self.value = normalizedValue
    }

    static let maximumLength = 64

    static func normalize(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }
}
