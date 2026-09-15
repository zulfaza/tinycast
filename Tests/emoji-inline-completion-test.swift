import Foundation

@main
@MainActor
struct EmojiInlineCompletionTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            print("FAIL: \(label)")
            failures += 1
        }
    }

    static func main() {
        let token = EmojiCompletionToken.precedingCaret(in: "hello :wave", caretUTF16Offset: 11)
        expect(token?.query == "wave", "finds an open colon token")
        expect(token?.replacementRange == NSRange(location: 6, length: 5), "range covers token")
        let emojiPrefix = EmojiCompletionToken.precedingCaret(
            in: "😀 :wave", caretUTF16Offset: 8)
        expect(
            emojiPrefix?.replacementRange == NSRange(location: 3, length: 5),
            "uses UTF-16 range")
        let wrapped = EmojiCompletionToken.precedingCaret(in: "say :+1:", caretUTF16Offset: 8)
        expect(wrapped?.query == "+1", "supports wrapped colon queries")
        expect(
            wrapped?.replacementRange == NSRange(location: 4, length: 4),
            "wrapped range includes colons")
        let wrappedWithPrefix = EmojiCompletionToken.precedingCaret(
            in: "😀 say :+1:", caretUTF16Offset: 11)
        expect(
            wrappedWithPrefix?.replacementRange == NSRange(location: 7, length: 4),
            "wrapped range stays UTF-16 correct after emoji")
        expect(
            EmojiCompletionToken.precedingCaret(in: "http://wave", caretUTF16Offset: 11) == nil,
            "does not complete URL fragments")
        expect(
            EmojiCompletionToken.precedingCaret(in: "😀 :wave", caretUTF16Offset: 1) == nil,
            "rejects a caret inside a UTF-16 surrogate pair")
        let midCaret = EmojiCompletionToken.precedingCaret(
            in: "say :wave later", caretUTF16Offset: 9)
        expect(midCaret?.replacementRange == NSRange(location: 4, length: 5), "range ends at caret")
        if let midCaret {
            let text = ("say :wave later" as NSString)
                .replacingCharacters(in: midCaret.replacementRange, with: "👋")
            expect(text == "say 👋 later", "replacement preserves text after a mid-caret token")
        }
        expect(
            EmojiCompletionToken.precedingCaret(in: "word:wave", caretUTF16Offset: 9) == nil,
            "requires a token boundary")
        expect(
            EmojiCompletionToken.precedingCaret(
                in: "say :wave", caretUTF16Offset: 9, selectedLength: 1) == nil,
            "does not replace an active selection")
        expect(
            EmojiCompletionToken.precedingCaret(in: "say :", caretUTF16Offset: 5) == nil,
            "does not suggest an empty query")

        if failures == 0 {
            print("emoji-inline-completion-test: all checks passed")
        } else {
            print("emoji-inline-completion-test: \(failures) failure(s)")
            exit(1)
        }
    }
}
