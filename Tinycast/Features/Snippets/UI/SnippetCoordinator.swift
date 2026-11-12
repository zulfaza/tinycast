import AppKit
import SwiftUI

@MainActor
@Observable
final class SnippetCoordinator {
    private(set) var editor: SnippetEditorSession?
    var isEditingSnippet: Bool { editor != nil }
    private let store: SnippetsStore
    private let listener: SnippetKeywordListener
    private let injector: TextInjector
    private let clipboardStore: ClipboardStore
    private let appIndex: AppIndex
    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let palette: PaletteState
    /// Routed out so `MessageHUDController` stays owned by `AppCore`.
    private let showMessage: @MainActor (String, DialogTone) -> Void
    /// The consent dialog stays owned by the composition root.
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
        palette: PaletteState,
        showMessage: @escaping @MainActor (String, DialogTone) -> Void,
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
        self.palette = palette
        self.showMessage = showMessage
        self.core = core
    }

    // MARK: - Feature switch

    func revealSnippetsInFinder() {
        NSWorkspace.shared.open(store.snippetsDirectory)
    }

    /// Points the library at a folder as it is; nothing is moved out of the old one.
    func chooseSnippetsFolder() {
        guard
            let url = FolderPicker.choose(
                message: String(localized: "Choose the folder your snippets are kept in."),
                startingAt: store.snippetsDirectory)
        else { return }
        settings.snippetsFolder = AppPaths.contentFolderSetting(for: url, named: "Snippets")
    }

    func resetSnippetsFolder() {
        settings.snippetsFolder = nil
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
                    title: String(localized: "Enable snippets?"),
                    message: String(
                        localized: """
                            Keyword expansion requires the Accessibility permission. Keystrokes stay on \
                            this Mac.
                            """),
                    symbol: "curlybraces", confirmTitle: String(localized: "Continue"), tone: .neutral,
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
        let commands: Set<CommandID> = [.searchSnippets, .createSnippet]
        appIndex.setCommandsVisible(commands, settings.snippetsEnabled)
        appIndex.setCommandsListed(commands, settings.snippetsShowInLauncher)
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
        if palette.mode == .snippetEditor { cancelSnippetEditing() }
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
    func showSnippets(query: String = "") {
        guard settings.snippetsEnabled else { return }
        paletteCoordinator.togglePalette(mode: .snippets, seeding: query.isEmpty ? nil : query)
    }

    func editSnippet(_ record: StoredSnippet?) {
        guard settings.snippetsEnabled else { return }
        editor = SnippetEditorSession(record: record)
        paletteCoordinator.showPalette(mode: .snippetEditor)
    }

    /// Starts from the text selected in the app in front, read through Accessibility, never ⌘C.
    func createSnippetFromSelection() {
        guard settings.snippetsEnabled else { return }
        let selection = paletteCoordinator.targetApp.flatMap(AccessibilityText.selection(in:))
        createSnippet(name: "", text: selection ?? "", keyword: "")
    }

    /// A link's batch, written only once the reader agrees; copies already here are skipped.
    func importSnippets(offered incoming: [Snippet]) async {
        guard settings.snippetsEnabled, !incoming.isEmpty else { return }
        guard
            await core.confirm(
                title: String(localized: "Add \(incoming.count) snippets from a link?"),
                message: ListFormatter.localizedString(byJoining: incoming.map(\.name)),
                symbol: "curlybraces", confirmTitle: String(localized: "Add"), tone: .neutral,
                confirmRole: .standard)
        else { return }
        // Matched as a backup import matches, so the same link twice leaves no second copy.
        let existing = Set(store.snippets.map { [$0.snippet.name, $0.snippet.text] })
        let fresh = incoming.filter { !existing.contains([$0.name, $0.text]) }
        guard !fresh.isEmpty else {
            return core.showMessage(String(localized: "Nothing to Import"), tone: .neutral)
        }
        do {
            let created = try await store.importSnippets(fresh)
            core.showMessage(String(localized: "Imported \(created.count) snippets."))
        } catch {
            await core.showNotice(
                title: String(localized: "Import Failed"), message: error.localizedDescription,
                symbol: "curlybraces", tone: .danger)
        }
    }

    /// A new snippet already filled in, from a link; nothing is written until it is saved.
    func createSnippet(name: String, text: String, keyword: String) {
        guard settings.snippetsEnabled else { return }
        let editor = SnippetEditorSession(record: nil)
        editor.name = name
        editor.text = text
        editor.keyword = keyword
        self.editor = editor
        paletteCoordinator.showPalette(mode: .snippetEditor)
    }

    func requestSnippetSave() {
        guard settings.snippetsEnabled, let editor, editor.canSave else { return }
        editor.isSaving = true
    }

    func saveSnippet(_ editor: SnippetEditorSession) async {
        guard settings.snippetsEnabled, !Task.isCancelled, self.editor === editor else { return }
        let snippet = editor.snippet
        defer { editor.isSaving = false }
        do {
            if var record = editor.record {
                record.snippet = snippet
                try await store.save(record)
            } else {
                try await store.create(snippet)
            }
            guard !Task.isCancelled, self.editor === editor else { return }
            cancelSnippetEditing()
        } catch {
            guard !Task.isCancelled, self.editor === editor else { return }
            editor.errorMessage = error.localizedDescription
        }
    }

    func cancelSnippetEditing() {
        guard palette.mode == .snippetEditor else { return }
        if !palette.pop(preservingSelection: true) {
            paletteCoordinator.hidePalette()
            palette.prepare(mode: .launcher)
        }
        editor = nil
    }

    func editorDidClose(_ editor: SnippetEditorSession) {
        if self.editor === editor { self.editor = nil }
    }

    func showSnippetInFinder(_ record: StoredSnippet) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(record.fileURL)
    }

    func toggleSnippetPinned(id: StoredSnippet.ID) async {
        guard settings.snippetsEnabled, var record = store.record(id: id) else { return }
        record.snippet.isPinned.toggle()
        do {
            try await store.save(record)
        } catch {
            await core.showNotice(
                title: String(localized: "Couldn’t Save the Change"),
                message: error.localizedDescription, symbol: "pin", tone: .danger)
            return
        }
        guard palette.mode == .snippets,
            let index = store.browserRows(matching: palette.query).firstIndex(where: { $0.id == id })
        else { return }
        palette.selection = index
    }

    func deleteSnippet(id: StoredSnippet.ID) async {
        guard settings.snippetsEnabled, let record = store.record(id: id) else { return }
        guard
            await core.confirm(
                title: String(localized: "Delete “\(record.snippet.name)”?"),
                message: String(
                    localized: "This removes \(record.fileURL.lastPathComponent) from your snippets folder."),
                symbol: "doc.text", confirmTitle: String(localized: "Delete"))
        else { return }
        do {
            try await store.delete(id: id)
        } catch {
            await core.showNotice(
                title: String(localized: "Couldn’t Delete “\(record.snippet.name)”"),
                message: error.localizedDescription, symbol: "doc.text", tone: .danger)
        }
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
        paletteCoordinator.popToRootNow()
        expandSnippet(id: id, target: target, userArguments: userArguments)
    }

    func promptedArguments(for record: StoredSnippet) -> [SnippetTemplateEngine.MissingArgument] {
        SnippetTemplateEngine.declaredArguments(in: record, snippets: store.snippets)
    }

    func performFromPalette(
        _ action: SnippetDefaultAction, id: StoredSnippet.ID, userArguments: [String: String]
    ) {
        switch action {
        case .paste: expandSnippetFromPalette(id: id, userArguments: userArguments)
        case .copy: copySnippetFromPalette(id: id, userArguments: userArguments)
        }
    }

    /// Unmarked, so the expansion enters clipboard history like any other copy.
    func copySnippetFromPalette(id: StoredSnippet.ID, userArguments: [String: String]) {
        let target = windowController.previousTarget
        paletteCoordinator.hidePalette()
        let records = store.snippets
        guard let record = records.first(where: { $0.id == id }) else { return }
        let output = settings.snippetsOutput
        let context = injector.captureExpansionContext(
            target: target,
            clipboardHistory: clipboardHistoryForExpansion())
        let result = SnippetTemplateEngine.expand(
            record, snippets: records, context: context, userArguments: userArguments, output: output)
        guard result.missingArguments.isEmpty else {
            promptSnippetArguments(
                record: record,
                records: records,
                context: context,
                missingArgs: result.missingArguments,
                userArguments: userArguments,
                output: output,
                onCancel: { target?.restoreFocus() },
                onExpanded: { [weak self] result in
                    self?.copy(result, of: record, output: output)
                    target?.restoreFocus()
                })
            return
        }
        copy(result, of: record, output: output)
    }

    private func copy(
        _ result: SnippetTemplateEngine.ExpansionResult, of record: StoredSnippet,
        output: SnippetExpansionOutput
    ) {
        let injected = Self.injectedText(result, output: output)
        let item = NSPasteboardItem()
        guard item.setString(injected.text, forType: .string) else { return }
        for representation in injected.content.representations {
            item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return }
        store.recordUse(id: record.id)
        guard record.snippet.showsConfirmation || settings.snippetsCompletionFeedback else { return }
        showMessage(String(localized: "Copied \(record.snippet.name)"), .success)
    }

    /// A shortcut lands where the caret is; over the palette, that's what the palette covered.
    func expandSnippetFromHotKey(id: StoredSnippet.ID) {
        guard settings.snippetsEnabled, store.record(id: id)?.snippet.isEnabled == true else {
            return
        }
        if windowController.isVisible {
            expandSnippetFromPalette(id: id)
            return
        }
        // A window of ours that isn't an editor, such as Settings, has no caret to type at.
        guard let target = InjectionTarget.current() else {
            showMessage(String(localized: "Click into a text field first"), .neutral)
            return
        }
        expandSnippet(id: id, target: target)
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
        let context = injector.captureExpansionContext(
            target: target,
            clipboardHistory: clipboardHistoryForExpansion())
        let result = SnippetTemplateEngine.expand(
            record,
            snippets: records,
            context: context,
            userArguments: userArguments,
            output: output ?? settings.snippetsOutput)
        // A typed keyword leaves nothing selected, so only an insertion asked for borrows a ⌘C.
        guard automaticGeneration == nil, result.readsSelection, context.selection.isEmpty,
            let app = target?.externalApp
        else {
            finishExpansion(
                record,
                records: records,
                context: context,
                result: result,
                target: target,
                expectedKeyword: expectedKeyword,
                keywordLength: keywordLength,
                automaticGeneration: automaticGeneration,
                userArguments: userArguments,
                output: output,
                injectionDelay: injectionDelay,
                showsCompletionFeedback: showsCompletionFeedback)
            return
        }
        Task {
            var context = context
            context.selection = await injector.copySelection(from: app) ?? ""
            let records = store.snippets
            guard let record = records.first(where: { $0.id == id }) else { return }
            finishExpansion(
                record,
                records: records,
                context: context,
                result: SnippetTemplateEngine.expand(
                    record, snippets: records, context: context,
                    userArguments: userArguments, output: output ?? settings.snippetsOutput),
                target: target,
                expectedKeyword: nil,
                keywordLength: 0,
                automaticGeneration: nil,
                userArguments: userArguments,
                output: output,
                injectionDelay: injectionDelay,
                showsCompletionFeedback: showsCompletionFeedback)
        }
    }

    private func finishExpansion(
        _ record: StoredSnippet,
        records: [StoredSnippet],
        context: SnippetTemplateEngine.ExpansionContext,
        result: SnippetTemplateEngine.ExpansionResult,
        target: InjectionTarget?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: UInt?,
        userArguments: [String: String],
        output: SnippetExpansionOutput?,
        injectionDelay: Duration?,
        showsCompletionFeedback: Bool?
    ) {
        let expansionOutput = output ?? settings.snippetsOutput
        let expansionDelay = injectionDelay ?? settings.snippetsInjectionDelay.duration
        let shouldShowFeedback =
            showsCompletionFeedback ?? (record.snippet.showsConfirmation || settings.snippetsCompletionFeedback)
        let confirmation = shouldShowFeedback ? String(localized: "Inserted \(record.snippet.name)") : nil
        if !result.missingArguments.isEmpty {
            promptSnippetArguments(
                record: record,
                records: records,
                context: context,
                missingArgs: result.missingArguments,
                userArguments: userArguments,
                output: expansionOutput,
                onCancel: { [weak self] in
                    self?.injector.cancelArgumentPrompt(
                        automaticGeneration: automaticGeneration,
                        target: target)
                },
                onExpanded: { [weak self] result in
                    self?.completeSnippetExpansion(
                        result,
                        recordID: record.id,
                        target: target,
                        expectedKeyword: expectedKeyword,
                        keywordLength: keywordLength,
                        automaticGeneration: automaticGeneration,
                        confirmation: confirmation,
                        injectionDelay: expansionDelay,
                        output: expansionOutput)
                })
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
        userArguments: [String: String],
        output: SnippetExpansionOutput,
        onCancel: @escaping @MainActor () -> Void,
        onExpanded: @escaping @MainActor (SnippetTemplateEngine.ExpansionResult) -> Void
    ) {
        // The open dialog would refuse this prompt, and its end must not clear the flag under it.
        guard !core.isShowingDialog else { return onCancel() }
        listener.isPromptingForArguments = true
        Task {
            let arguments = await core.fillSnippetArguments(
                snippetName: record.snippet.name,
                arguments: missingArgs)
            listener.isPromptingForArguments = false
            guard let arguments else { return onCancel() }
            onExpanded(
                SnippetTemplateEngine.expand(
                    record,
                    snippets: records,
                    context: context,
                    userArguments: userArguments.merging(arguments) { _, prompted in prompted },
                    output: output))
        }
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
        injector.deliver(
            Self.injectedText(result, output: output),
            target: target,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            injectionDelay: injectionDelay,
            onDelivered: { [weak self] in
                guard let self else { return }
                self.store.recordUse(id: recordID)
                if let confirmation { self.showMessage(confirmation, .success) }
            })
    }

    private static func injectedText(
        _ result: SnippetTemplateEngine.ExpansionResult, output: SnippetExpansionOutput
    ) -> InjectedText {
        switch output {
        case .markdown:
            InjectedText(
                markdown: result.text,
                plainText: SnippetMarkdownSerializer.plainText(from: result.text),
                cursorOffsetFromEnd: result.cursorOffsetFromEnd)
        case .plainText:
            InjectedText(result.text, cursorOffsetFromEnd: result.cursorOffsetFromEnd)
        }
    }
}
