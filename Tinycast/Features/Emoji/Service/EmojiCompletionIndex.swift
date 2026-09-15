import Foundation

/// Bridges the pure colon-token parser to the existing CLDR/frequency index.
@MainActor
enum EmojiCompletionIndex {
    static func suggestions(
        for token: EmojiCompletionToken,
        index: EmojiIndex,
        frequent: FrequentEmojiStore,
        customKeywords: [EmojiKeyword] = [],
        limit: Int = 6
    ) -> [EmojiCompletionSuggestion] {
        index.search(
            token.query, frequent: frequent, customKeywords: customKeywords, limit: limit
        )
        .map { EmojiCompletionSuggestion(entry: $0, replacementRange: token.replacementRange) }
    }
}
