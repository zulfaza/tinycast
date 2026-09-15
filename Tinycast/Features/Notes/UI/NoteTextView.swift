import AppKit
import Carbon.HIToolbox

struct NoteInlineCompletion: Sendable {
    let text: String
    let replacementRange: NSRange
}

@MainActor
final class NoteTextView: NSTextView, InjectableTextView {
    var editorUndoManager: UndoManager?
    var completionProvider: @MainActor (
        _ text: String, _ caretUTF16Offset: Int, _ selectedLength: Int
    ) -> NoteInlineCompletion? = { _, _, _ in nil } {
        didSet { refreshCompletion() }
    }

    private var completion: NoteInlineCompletion?

    override var undoManager: UndoManager? { editorUndoManager }

    override func didChangeText() {
        super.didChangeText()
        refreshCompletion()
    }

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        refreshCompletion()
    }

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        refreshCompletion()
    }

    override func keyDown(with event: NSEvent) {
        let acceptsCompletion =
            !hasMarkedText() && completion != nil
                && (event.keyCode == UInt16(kVK_Tab) || event.keyCode == UInt16(kVK_Return))
        guard acceptsCompletion, let completion else {
            super.keyDown(with: event)
            return
        }
        insertText(completion.text, replacementRange: completion.replacementRange)
        setSelectedRange(
            NSRange(
                location: completion.replacementRange.location + completion.text.utf16.count,
                length: 0))
        refreshCompletion()
    }

    func refreshCompletion() {
        let selection = selectedRange()
        completion = completionProvider(string, selection.location, selection.length)
    }
}
