import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Owns the floating editor so snippet changes never take the user to Settings.
@MainActor
final class SnippetWindowController: NSObject, NSWindowDelegate {
    private static let size = CGSize(width: 760, height: 475)
    private let store: SnippetsStore
    private let emojiIndex: EmojiIndex
    private var panel: SnippetPanel?
    private var currentRecord: StoredSnippet?
    private var hasEditor = false
    private var escapeMonitor: Any?

    init(store: SnippetsStore, emojiIndex: EmojiIndex) {
        self.store = store
        self.emojiIndex = emojiIndex
    }

    func show(record: StoredSnippet?, center: Bool = true) {
        hasEditor = true
        currentRecord = record
        let panel = ensurePanel()
        let root = SnippetEditorView(record: record) { [weak self] in
            self?.close()
        }
        panel.contentView = NSHostingView(
            rootView: root
                .environment(store)
                .environment(emojiIndex))
        if center, !panel.isVisible { panel.center() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        hasEditor = false
        currentRecord = nil
        panel?.close()
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else if hasEditor {
            show(record: currentRecord, center: false)
        }
    }

    func windowWillClose(_ notification: Notification) {
        hasEditor = false
        currentRecord = nil
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        panel = nil
    }

    private func ensurePanel() -> SnippetPanel {
        if let panel { return panel }
        let panel = SnippetPanel(size: Self.size)
        panel.delegate = self
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self,
                self.panel?.isKeyWindow == true,
                event.keyCode == UInt16(kVK_Escape),
                event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else { return event }
            self.close()
            return nil
        }
        self.panel = panel
        return panel
    }
}

@MainActor
private final class SnippetPanel: NSPanel {
    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        isRestorable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
