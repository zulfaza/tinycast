import AppKit
import SwiftUI

/// Owns the snippet flow: listener, browser, editor handoff, delivery, presence.
@MainActor
final class SnippetCoordinator {
    private let store: SnippetsStore
    private let listener: SnippetKeywordListener
    private let injector: TextInjector
    private let clipboardStore: ClipboardStore
    private let appIndex: AppIndex
    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let editorPanel: SnippetEditorPanelController
    /// Routed out so `MessageHUDController` stays owned by `AppCore`.
    private let showMessage: @MainActor (String) -> Void
    /// The consent dialog and standalone editor panel are owned by this coordinator.
    private unowned let core: AppCore

    var interfaceMetrics: InterfaceMetrics { settings.interfaceSize.metrics }

    init(
        store: SnippetsStore,
        listener: SnippetKeywordListener,
        injector: TextInjector,
        clipboardStore: ClipboardStore,
        appIndex: AppIndex,
        settings: AppSettings,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        showMessage: @escaping @MainActor (String) -> Void,
        core: AppCore
    ) {
        self.store = store
        self.listener = listener
        self.injector = injector
        self.clipboardStore = clipboardStore
        self.appIndex = appIndex
        self.settings = settings
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.editorPanel = SnippetEditorPanelController(store: store, settings: settings)
        self.showMessage = showMessage
        self.core = core
    }

    // MARK: - Feature switch

    func revealSnippetsInFinder() {
        NSWorkspace.shared.open(store.snippetsDirectory)
    }

    /// The switch funnels here so enabling, which is also consent, confirms first.
    func setSnippetsEnabled(_ enabled: Bool) {
        guard enabled != settings.snippetsEnabled else { return }
        if !enabled {
            settings.snippetsEnabled = false
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Enable snippets?",
                    message:
                        "Keyword expansion requires the Accessibility permission. Keystrokes stay on this Mac.",
                    symbol: "curlybraces", confirmTitle: "Continue", tone: .neutral,
                    confirmRole: .standard)
            else { return }

            settings.snippetsEnabled = true
            // The one prompt for this feature, raised from the gesture that asked for it.
            Permissions.ensureAccessibility()
        }
    }

    // MARK: - Feature presence

    /// Either switch off means the feature reaches the launcher not at all — rows and commands.
    func applySnippetsLauncherPresence() {
        let visible = settings.snippetsEnabled && settings.snippetsShowInLauncher
        appIndex.setCommandsVisible([.searchSnippets, .createSnippet], visible)
        appIndex.updateSnippets(visible ? store.snippets : [])
    }

    /// Reconciles everything the switch owns; off tears down in dependency order.
    func applySnippetsEnabled() {
        if settings.snippetsEnabled {
            Task { await store.start() }
            // An unchanged library publishes no snapshot, so re-project what the store holds.
            applySnippetsLauncherPresence()
            startSnippetKeywordListener()
            return
        }
        listener.stop()
        injector.cancelAutomaticExpansion()
        store.stop()
        applySnippetsLauncherPresence()
    }

    func applySnippetPolicy() {
        listener.updateTrigger(
            SnippetExpansionTrigger(
                mode: settings.snippetsTriggerMode,
                delimiter: settings.snippetsDelimiter,
                retainsDelimiter: settings.snippetsRetainsDelimiter))
        listener.updateExcludedBundleIDs(settings.snippetsExcludedApps)
        let directories = settings.snippetsSharedLibraries.map { URL(fileURLWithPath: $0) }
        store.setSharedLibraryDirectories(directories)
    }

    // MARK: - Browsing and editing

    /// The switch gates the browser, the way Search Files re-checks its own before opening.
    func showSnippets() {
        guard settings.snippetsEnabled else { return }
        paletteCoordinator.togglePalette(mode: .snippets)
    }

    /// Opens the standalone editor with `record`; nil is a new snippet.
    func editSnippet(_ record: StoredSnippet?) {
        guard record.map(store.isWritable) ?? true else { return }
        let state: SnippetEditorState = record.map(SnippetEditorState.edit)
            ?? .create(Snippet(name: "", text: ""))
        openEditor(state: state)
    }

    /// Opens the standalone editor for a text clipboard item; non-text values do nothing.
    func saveClipboardAsSnippet(text: String?, name: String?) {
        guard let text else { return }
        openEditor(
            state: .create(
                Snippet(name: name ?? "Clipboard Snippet", text: text)))
    }

    private func openEditor(state: SnippetEditorState) {
        let size = CGSize(
            width: interfaceMetrics.size.panelWidth, height: interfaceMetrics.size.panelHeight)
        let frame = windowController.frameForAuxiliaryPanel(size: size)
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        editorPanel.open(state: state, frame: frame) { [weak core] in
            core?.snippetCoordinator.editorDidClose()
        }
    }

    var isEditingSnippet: Bool { editorPanel.isOpen }

    func toggleEditor() {
        guard editorPanel.hasEditor else { return }
        if editorPanel.isVisible {
            editorPanel.hide()
        } else {
            editorPanel.show()
        }
    }

    private func editorDidClose() {
        editorPanel.clearEditor()
    }

    func showSnippetInFinder(_ record: StoredSnippet) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(record.fileURL)
    }

    // MARK: - Expansion

    /// How far back `{clipboard offset=N}` reaches; deeper isn't a snippet idiom.
    private static let clipboardHistoryDepth = 20

    func startSnippetKeywordListener() {
        // `beginAutomaticExpansion` is the gate, so this callback doesn't re-check anything.
        listener.start(
            onUserActivity: { [weak self] in self?.injector.cancelAutomaticExpansion() },
            onMatch: { [weak self] id, keyword, keywordLength, target in
                guard let self,
                    let generation = self.injector.beginAutomaticExpansion(target: target)
                else { return }
                self.expandSnippet(
                    id: id,
                    target: target,
                    expectedKeyword: keyword,
                    keywordLength: keywordLength,
                    automaticGeneration: generation)
            })
    }

    /// Recent copies, newest first; the live pasteboard leads, the poller may lag behind.
    func clipboardHistoryForExpansion() -> [String] {
        var history = clipboardStore.items
            .filter { $0.kind == .text }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.clipboardHistoryDepth)
            .compactMap(\.text)
        if let current = NSPasteboard.general.string(forType: .string), current != history.first {
            history.insert(current, at: 0)
        }
        return history
    }

    /// The browser's ↵. The target has to be read before the panel hides, as the launcher's does.
    func expandSnippetFromPalette(id: StoredSnippet.ID) {
        expandSnippetFromPalette(id: id, userArguments: [:])
    }

    func expandSnippetFromPalette(
        id: StoredSnippet.ID, userArguments: [String: String]
    ) {
        let target = windowController.previousTarget
        // One of our own editors is only reachable again once the palette hands key back to it.
        paletteCoordinator.hidePalette(restoreFocus: target?.ownEditor != nil)
        expandSnippet(id: id, target: target, userArguments: userArguments)
    }

    func promptedArguments(for record: StoredSnippet) -> [SnippetTemplateEngine.MissingArgument] {
        SnippetTemplateEngine.declaredArguments(in: record, snippets: store.snippets)
    }

    func expandSnippet(
        id: StoredSnippet.ID,
        target: InjectionTarget?,
        expectedKeyword: String? = nil,
        keywordLength: Int = 0,
        automaticGeneration: UInt? = nil,
        userArguments: [String: String] = [:],
        output: SnippetExpansionOutput? = nil,
        injectionDelay: Duration? = nil,
        showsCompletionFeedback: Bool? = nil
    ) {
        let records = store.snippets
        guard let record = records.first(where: { $0.id == id }) else {
            injector.cancelArgumentPrompt(
                automaticGeneration: automaticGeneration,
                target: target)
            return
        }
        // Only the interactive path needs this: it must fail before the prompt, not after.
        if automaticGeneration == nil {
            guard injector.prepareInteractiveExpansion(target: target) else { return }
        }
        let expansionOutput = output ?? settings.snippetsOutput
        let expansionDelay = injectionDelay ?? settings.snippetsInjectionDelay.duration
        let shouldShowFeedback =
            showsCompletionFeedback ?? (record.snippet.showsConfirmation || settings.snippetsCompletionFeedback)
        let confirmation = shouldShowFeedback ? "Inserted \(record.snippet.name)" : nil
        let context = injector.captureExpansionContext(
            target: target,
            clipboardHistory: clipboardHistoryForExpansion())
        let result = SnippetTemplateEngine.expand(
            record,
            snippets: records,
            context: context,
            userArguments: userArguments,
            output: expansionOutput)
        if !result.missingArguments.isEmpty {
            promptSnippetArguments(
                record: record,
                records: records,
                context: context,
                missingArgs: result.missingArguments,
                target: target,
                expectedKeyword: expectedKeyword,
                keywordLength: keywordLength,
                automaticGeneration: automaticGeneration,
                confirmation: confirmation,
                userArguments: userArguments,
                output: expansionOutput,
                injectionDelay: expansionDelay)
            return
        }
        completeSnippetExpansion(
            result,
            recordID: record.id,
            target: target,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            confirmation: confirmation,
            injectionDelay: expansionDelay,
            output: expansionOutput)
    }

    private func promptSnippetArguments(
        record: StoredSnippet,
        records: [StoredSnippet],
        context: SnippetTemplateEngine.ExpansionContext,
        missingArgs: [SnippetTemplateEngine.MissingArgument],
        target: InjectionTarget?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: UInt?,
        confirmation: String?,
        userArguments: [String: String],
        output: SnippetExpansionOutput,
        injectionDelay: Duration
    ) {
        listener.isPromptingForArguments = true
        defer { listener.isPromptingForArguments = false }
        guard
            let arguments = SnippetArgumentsPrompt.run(
                snippetName: record.snippet.name,
                arguments: missingArgs,
                metrics: settings.interfaceSize.metrics)
        else {
            injector.cancelArgumentPrompt(
                automaticGeneration: automaticGeneration,
                target: target)
            return
        }

        let result = SnippetTemplateEngine.expand(
            record,
            snippets: records,
            context: context,
            userArguments: userArguments.merging(arguments) { _, prompted in prompted },
            output: output)
        completeSnippetExpansion(
            result,
            recordID: record.id,
            target: target,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            confirmation: confirmation,
            injectionDelay: injectionDelay,
            output: output)
    }

    private func completeSnippetExpansion(
        _ result: SnippetTemplateEngine.ExpansionResult,
        recordID: StoredSnippet.ID,
        target: InjectionTarget?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: UInt?,
        confirmation: String?,
        injectionDelay: Duration,
        output: SnippetExpansionOutput
    ) {
        let injected: InjectedText
        switch output {
        case .markdown:
            injected = InjectedText(
                markdown: result.text,
                plainText: SnippetMarkdownSerializer.plainText(from: result.text),
                cursorOffsetFromEnd: result.cursorOffsetFromEnd)
        case .plainText:
            injected = InjectedText(result.text, cursorOffsetFromEnd: result.cursorOffsetFromEnd)
        }
        injector.deliver(
            injected,
            target: target,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            injectionDelay: injectionDelay,
            onDelivered: { [weak self] in
                guard let self else { return }
                self.store.recordUse(id: recordID)
                if let confirmation { self.showMessage(confirmation) }
            })
    }
}

@MainActor
private final class SnippetEditorPanelController: NSObject, NSWindowDelegate {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private let store: SnippetsStore
    private let settings: AppSettings
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var onDismiss: (() -> Void)?

    init(store: SnippetsStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    var hasEditor: Bool { panel != nil }
    var isOpen: Bool { panel != nil }
    var isVisible: Bool { panel?.isVisible == true }

    func open(state: SnippetEditorState, frame: NSRect, onDismiss: @escaping () -> Void) {
        panel?.close()
        self.onDismiss = onDismiss

        let view = SnippetEditorView(state: state, metrics: settings.interfaceSize.metrics) {
            [weak self] in self?.panel?.close()
        }
        hostingController = NSHostingController(rootView: AnyView(view.environment(store)))

        let panel = Panel(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.title = state.isEditing ? "Edit Snippet" : "Add Snippet"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.delegate = self
        panel.contentViewController = hostingController
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.cornerRadius = settings.interfaceSize.metrics.radius.panel
        panel.contentView?.layer?.masksToBounds = true
        panel.setFrame(frame, display: false)
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.selectNextKeyView(nil)
    }

    func show() {
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func clearEditor() {
        panel = nil
        hostingController = nil
        onDismiss = nil
    }

    func windowWillClose(_ notification: Notification) {
        onDismiss?()
    }
}
