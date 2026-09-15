import AppKit
import Carbon.HIToolbox

/// Tinycast-owned text view hook; it never observes or intercepts another app's keystrokes.
@MainActor
class EmojiInlineCompletionTextView: NSTextView {
    var completionTone: EmojiSkinTone = .none
    var suggestionsForText: (
        _ text: String, _ caretUTF16Offset: Int, _ selectedLength: Int
    ) -> [EmojiCompletionSuggestion] = { _, _, _ in [] } {
        didSet { refreshSuggestions() }
    }
    var onSuggestionsChanged: @MainActor ([EmojiCompletionSuggestion]) -> Void = { _ in }
    var onTextChanged: @MainActor (String) -> Void = { _ in }

    private(set) var suggestions: [EmojiCompletionSuggestion] = []

    override func didChangeText() {
        super.didChangeText()
        refreshSuggestions()
        onTextChanged(string)
    }

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        refreshSuggestions()
    }

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        refreshSuggestions()
    }

    override func keyDown(with event: NSEvent) {
        let acceptsCompletion =
            !hasMarkedText() && !suggestions.isEmpty
            && (event.keyCode == UInt16(kVK_Tab) || event.keyCode == UInt16(kVK_Return))
        guard acceptsCompletion, let suggestion = suggestions.first else {
            super.keyDown(with: event)
            return
        }
        let glyph = suggestion.entry.display(tone: completionTone)
        insertText(glyph, replacementRange: suggestion.replacementRange)
        setSelectedRange(
            NSRange(
                location: suggestion.replacementRange.location + glyph.utf16.count,
                length: 0))
        refreshSuggestions()
        onTextChanged(string)
    }

    func refreshSuggestions() {
        let selection = selectedRange()
        suggestions = suggestionsForText(string, selection.location, selection.length)
        onSuggestionsChanged(suggestions)
    }
}
