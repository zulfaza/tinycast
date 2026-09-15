import Foundation

/// The colon expression immediately before a text view's caret.
struct EmojiCompletionToken: Equatable, Sendable {
    let query: String
    let replacementRange: NSRange

    static func precedingCaret(
        in text: String, caretUTF16Offset: Int, selectedLength: Int = 0
    ) -> Self? {
        let length = (text as NSString).length
        guard selectedLength == 0, caretUTF16Offset >= 0, caretUTF16Offset <= length else {
            return nil
        }
        let caretIndex = String.Index(utf16Offset: caretUTF16Offset, in: text)
        guard caretIndex.samePosition(in: text) != nil else { return nil }

        let prefix = (text as NSString).substring(to: caretUTF16Offset)
        let searchPrefix = prefix.last == ":" ? String(prefix.dropLast()) : prefix
        guard let colon = searchPrefix.lastIndex(of: ":") else { return nil }
        let beforeColon = searchPrefix[..<colon]
        if let previous = beforeColon.last,
            previous.isLetter || previous.isNumber || previous == "_"
        {
            return nil
        }

        let query = String(searchPrefix[searchPrefix.index(after: colon)...])
        guard !query.isEmpty, !query.contains(":"),
            query.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "_" })
        else { return nil }
        let location = colon.utf16Offset(in: text)
        return Self(
            query: query,
            replacementRange: NSRange(location: location, length: caretUTF16Offset - location))
    }
}

/// A ranked candidate and the range its glyph replaces.
struct EmojiCompletionSuggestion: Equatable, Hashable, Identifiable, Sendable {
    let entry: EmojiEntry
    let replacementRange: NSRange

    var id: String { entry.id }
}
