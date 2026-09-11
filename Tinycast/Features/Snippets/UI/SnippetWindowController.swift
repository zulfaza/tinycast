import AppKit
import SwiftUI

/// Owns the floating editor so snippet changes never take the user to Settings.
@MainActor
final class SnippetWindowController: NSObject, NSWindowDelegate {
    private static let size = CGSize(width: 760, height: 560)
    private let store: SnippetsStore
    private let emojiIndex: EmojiIndex
    private var panel: SnippetPanel?

    init(store: SnippetsStore, emojiIndex: EmojiIndex) {
        self.store = store
        self.emojiIndex = emojiIndex
    }

    func show(record: StoredSnippet?) {
        let panel = ensurePanel()
        let root = SnippetEditorView(record: record) { [weak self] in
            self?.close()
        }
        panel.contentView = NSHostingView(
            rootView: root
                .environment(store)
                .environment(emojiIndex))
        if !panel.isVisible { panel.center() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }

    private func ensurePanel() -> SnippetPanel {
        if let panel { return panel }
        let panel = SnippetPanel(size: Self.size)
        panel.delegate = self
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
