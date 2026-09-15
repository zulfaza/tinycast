import AppKit
import Carbon.HIToolbox

enum Paster {
    /// Stamped on Tinycast's own synthetic keystrokes so the snippet keyword tap can skip them.
    static let tinycastEventTag: Int64 = 0x54494E59

    /// Write the item and paste it into `previousApp`, activating it so ⌘V lands there.
    @MainActor @discardableResult
    static func paste(
        _ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication?
    ) -> Bool {
        guard write(item, store: store) else { return false }
        previousApp?.activate()
        scheduleCommandV(after: .milliseconds(80))
        return true
    }

    @MainActor @discardableResult
    static func pasteAs(
        _ representation: ClipboardRepresentation, item: ClipboardItem,
        store: ClipboardStore, previousApp: NSRunningApplication?
    ) -> Bool {
        guard write(representation, item: item, store: store) else { return false }
        previousApp?.activate()
        scheduleCommandV(after: .milliseconds(80))
        return true
    }

    /// Put the item on the pasteboard without pasting; the marker stops re-capture.
    @MainActor @discardableResult
    static func copy(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        write(item, store: store)
    }

    @MainActor @discardableResult
    static func copyAs(
        _ representation: ClipboardRepresentation, item: ClipboardItem, store: ClipboardStore
    ) -> Bool {
        write(representation, item: item, store: store)
    }

    /// Put a string on the pasteboard unmarked, so it enters history like any other copy.
    @MainActor
    static func copyPlainText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString(text, forType: .string)
    }

    /// String counterpart of `paste`, marker-stamped so the text doesn't re-enter history.
    @MainActor
    static func pasteString(_ text: String, previousApp: NSRunningApplication?) {
        writeString(text)
        previousApp?.activate()
        scheduleCommandV(after: .milliseconds(80))
    }

    /// A file, pasted into `previousApp`; the receiver takes the file or its path, as it reads.
    @MainActor
    static func pasteFile(_ url: URL, previousApp: NSRunningApplication?) {
        PasteboardFiles.write(url, to: .general)
        previousApp?.activate()
        scheduleCommandV(after: .milliseconds(80))
    }

    /// String counterpart of `copy(_:store:)`.
    @MainActor
    static func copyString(_ text: String) {
        writeString(text)
    }

    /// String counterpart of `pasteInPlace`; the palette stays frontmost.
    @MainActor
    static func pasteStringInPlace(_ text: String, into app: NSRunningApplication?) {
        writeString(text)
        guard let pid = app?.processIdentifier else { return }
        scheduleCommandV(after: .milliseconds(50), toPid: pid)
    }

    @MainActor
    private static func writeString(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, ClipboardManager.internalType], owner: nil)
        pb.setString(text, forType: .string)
        pb.setData(Data(), forType: ClipboardManager.internalType)
    }

    /// Paste into `app` without activating it, so the palette stays open.
    @MainActor @discardableResult
    static func pasteInPlace(
        _ item: ClipboardItem, store: ClipboardStore, into app: NSRunningApplication?
    ) -> Bool {
        guard write(item, store: store) else { return false }
        if let pid = app?.processIdentifier {
            scheduleCommandV(after: .milliseconds(50), toPid: pid)
        }
        return true
    }

    @MainActor @discardableResult
    static func pasteAsInPlace(
        _ representation: ClipboardRepresentation, item: ClipboardItem, store: ClipboardStore,
        into app: NSRunningApplication?
    ) -> Bool {
        guard write(representation, item: item, store: store) else { return false }
        if let pid = app?.processIdentifier {
            scheduleCommandV(after: .milliseconds(50), toPid: pid)
        }
        return true
    }

    /// Whether anything was written; a vanished item leaves the pasteboard untouched.
    @MainActor @discardableResult
    static func write(
        _ item: ClipboardItem, store: ClipboardStore, to pb: NSPasteboard = .general
    ) -> Bool {
        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            pb.clearContents()
            pb.declareTypes([.string, ClipboardManager.internalType], owner: nil)
            pb.setString(text, forType: .string)
        case .image:
            guard let url = store.imageURL(for: item),
                let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else {
                return false
            }
            pb.clearContents()
            pb.declareTypes([.png, ClipboardManager.internalType], owner: nil)
            pb.setData(data, forType: .png)
        case .file:
            let urls = store.fileURLs(for: item)
            guard !urls.isEmpty,
                urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) })
            else { return false }
            guard PasteboardFiles.write(urls, to: pb) else { return false }
        }
        pb.setData(Data(), forType: ClipboardManager.internalType)
        // The poller skips marked writes, so this is the only promotion point.
        store.promote(item)
        return true
    }

    @MainActor @discardableResult
    static func write(
        _ representation: ClipboardRepresentation, item: ClipboardItem, store: ClipboardStore,
        to pb: NSPasteboard = .general
    ) -> Bool {
        guard !representation.values.isEmpty else { return false }
        let type = NSPasteboard.PasteboardType(representation.typeIdentifier)
        let items = representation.values.map { data in
            let item = NSPasteboardItem()
            item.setData(data, forType: type)
            return item
        }
        pb.clearContents()
        guard pb.writeObjects(items) else { return false }
        pb.setData(Data(), forType: ClipboardManager.internalType)
        store.promote(item)
        return true
    }

    /// Synthesize ⌘V, to `pid` alone when given, else through the system tap.
    @MainActor
    static func postCommandV(toPid pid: pid_t? = nil) {
        postCommand(key: CGKeyCode(kVK_ANSI_V), toPid: pid)
    }

    @MainActor
    private static func scheduleCommandV(after delay: Duration, toPid pid: pid_t? = nil) {
        Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            postCommandV(toPid: pid)
        }
    }

    /// Synthesize ⌘C, for reading a selection an app will not surface over Accessibility.
    @MainActor
    static func postCommandC(toPid pid: pid_t? = nil) {
        postCommand(key: CGKeyCode(kVK_ANSI_C), toPid: pid)
    }

    @MainActor
    private static func postCommand(key: CGKeyCode, toPid pid: pid_t?) {
        guard Permissions.ensureAccessibility() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: tinycastEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: tinycastEventTag)

        if let pid {
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
