import AppKit
import SwiftUI

struct SnippetsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(SnippetsStore.self) private var snippetsStore
    @Environment(AppSettings.self) private var settings

    @State private var pendingDeletion: StoredSnippet?

    var body: some View {
        @Bindable var settings = settings
        @Bindable var core = core
        return Form {
            FeatureSwitchSection(
                anchor: .snippetsSnippets,
                enableTitle: "Enable snippets",
                enableSubtitle:
                    "Reusable Markdown templates, expanded from the launcher or a typed keyword.",
                launcherSubtitle: "Find your snippets in launcher search.",
                // Enabling is also keyword-expansion consent, so it uses the confirming setter.
                isEnabled: Binding(
                    get: { settings.snippetsEnabled },
                    set: { core.snippetCoordinator.setSnippetsEnabled($0) }),
                showsInLauncher: $settings.snippetsShowInLauncher)

            if settings.snippetsEnabled, core.snippetListener.status == .needsAccessibility {
                Section {
                    LabeledContent {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                    } label: {
                        Label(
                            "Keyword expansion needs the Accessibility permission.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        Text(
                            "The same grant pasting uses. Launcher search keeps working meanwhile.")
                    }
                }
            }

            Group {
                shortcuts
                library
                libraryNotices
            }
            .settingsEnabled(settings.snippetsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.snippets)
        .alert(item: $pendingDeletion) { record in
            Alert(
                title: Text("Delete “\(record.snippet.name)”?"),
                message: Text(
                    "This removes \(record.fileURL.lastPathComponent) from your snippets folder."),
                primaryButton: .destructive(Text("Delete")) {
                    delete(record)
                },
                secondaryButton: .cancel())
        }
    }

    private var shortcuts: some View {
        Section {
            SettingsRow(title: "Search Snippets", anchor: .snippetsGlobalShortcut) {
                ShortcutRecorder(action: .command(.searchSnippets))
            }
        } header: {
            SettingsSectionHeader(.snippetsGlobalShortcut)
        } footer: {
            Text("Opens the snippets browser, whatever app you are in.")
        }
    }

    private var library: some View {
        Section {
            if sortedSnippets.isEmpty {
                Text(snippetsStore.state == .loading ? "Loading snippets…" : "No snippets yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedSnippets) { record in
                    SnippetSettingsRow(
                        record: record,
                        onEdit: { core.snippetCoordinator.editSnippet(record) },
                        onDelete: { pendingDeletion = record })
                }
            }

            LabeledContent {
                Button("Add…") { core.snippetCoordinator.editSnippet(nil) }
            } label: {
                SettingsRowTitle(.snippetsLibrary, "New Snippet")
                Text("Give the snippet a searchable name and an optional expansion keyword.")
            }

            LabeledContent {
                Button("Open Folder", action: core.snippetCoordinator.revealSnippetsInFinder)
                    .accessibilityHint("Reveals this Tinycast channel’s snippets folder in Finder.")
            } label: {
                SettingsRowTitle(.snippetsLibrary, "Snippets Folder")
                Text("Plain Markdown files in this channel’s Application Support folder.")
            }
        } header: {
            SettingsSectionHeader(.snippetsLibrary)
        }
    }

    @ViewBuilder
    private var libraryNotices: some View {
        if case .failed(let message) = snippetsStore.state {
            noticeSection(
                "Couldn’t load the snippet library", message, tint: .orange,
                retryHint: "Tries to load the snippet library again.")
        }

        if !snippetsStore.issues.isEmpty {
            noticeSection(
                snippetIssueTitle, snippetIssueMessage, tint: .orange,
                retryHint: "Reloads snippet files after you fix them on disk.")
        }

        // Keep library failures visible while the standalone editor is closed.
        if let operationError = snippetsStore.operationError {
            noticeSection(
                "The snippet operation failed", operationError, tint: .red, retryHint: nil)
        }
    }

    private func noticeSection(
        _ title: String, _ message: String, tint: Color, retryHint: String?
    ) -> some View {
        Section {
            LabeledContent {
                if let retryHint {
                    Button("Retry", action: snippetsStore.retry)
                        .accessibilityHint(retryHint)
                }
            } label: {
                Label(title, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(tint)
                Text(message)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var sortedSnippets: [StoredSnippet] {
        snippetsStore.snippets.sorted {
            $0.snippet.name.localizedCaseInsensitiveCompare($1.snippet.name) == .orderedAscending
        }
    }

    private var snippetIssueTitle: String {
        let count = snippetsStore.issues.count
        return count == 1
            ? "1 snippet file couldn’t be loaded" : "\(count) snippet files couldn’t be loaded"
    }

    private var snippetIssueMessage: String {
        let first = snippetsStore.issues[0]
        if snippetsStore.issues.count == 1 {
            return "\(first.fileURL.lastPathComponent): \(first.message)"
        }
        return
            "\(first.fileURL.lastPathComponent): \(first.message) Plus \(snippetsStore.issues.count - 1) more."
    }

    private func delete(_ record: StoredSnippet) {
        Task { try? await snippetsStore.delete(id: record.id) }
    }
}

private struct SnippetSettingsRow: View {
    let record: StoredSnippet
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: record.snippet.name, subtitle: metadata) {
            Image(systemName: "doc.text")
        } trailing: {
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Snippet")
            .accessibilityLabel("Edit \(record.snippet.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Snippet")
            .accessibilityLabel("Delete \(record.snippet.name)")
        }
    }

    private var metadata: String {
        let filename = record.fileURL.lastPathComponent
        guard let keyword = record.snippet.keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
            !keyword.isEmpty
        else { return filename }
        return "\(keyword) · \(filename)"
    }
}

struct SnippetEditorView: View {
    /// nil while adding; otherwise the record whose file (and revision) the save targets.
    let record: StoredSnippet?

    let onDismiss: () -> Void
    @Environment(SnippetsStore.self) private var store
    @FocusState private var isTemplateFocused: Bool
    @State private var showingIconPicker = false
    @State private var isIconHovered = false
    @State private var name: String
    @State private var iconSymbol: String?
    @State private var keyword: String
    @State private var text: String
    @State private var selection: TextSelection?
    @State private var isEnabled: Bool
    @State private var showsConfirmation: Bool
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(record: StoredSnippet?, onDismiss: @escaping () -> Void) {
        self.record = record
        self.onDismiss = onDismiss
        let snippet = record?.snippet
        _name = State(initialValue: snippet?.name ?? "")
        _iconSymbol = State(initialValue: snippet?.iconSymbol)
        _keyword = State(initialValue: snippet?.keyword ?? "")
        _text = State(initialValue: snippet?.text ?? "")
        _isEnabled = State(initialValue: snippet?.isEnabled ?? true)
        _showsConfirmation = State(initialValue: snippet?.showsConfirmation ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.lg) {
                Button(action: onDismiss) {
                    SymbolImage(name: "chevron.left", size: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
                Text("Snippets Guide")
                    .underline()
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: Theme.Spacing.xxxl) {
                templateEditor
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    nameAndIconField
                    field(
                        title: "Keyword", placeholder: "Optional, for example !notes", text: $keyword,
                        hint: "Optional. Type this to expand the snippet.")
                    optionToggle(
                        "Enabled", isOn: $isEnabled, detail: "Disabled snippets cannot be expanded.")
                    optionToggle(
                        "Show confirmation", isOn: $showsConfirmation, detail: "Confirm after insertion.")
                }
                .frame(width: 270)
            }
            .padding(.top, Theme.Spacing.xxxl)

            Spacer(minLength: Theme.Spacing.xl)

            HStack {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: record == nil ? "doc.badge.plus" : "doc.text", size: 15)
                    Text(record == nil ? "Create Snippet" : "Edit Snippet")
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: Theme.Size.snippetControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .padding(.leading, Theme.Spacing.md)
                }
                Spacer()
                Button(action: save) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Save Snippet")
                        KeyCapChip(text: "⌘", scale: .compact)
                        KeyCapChip(text: "↵", scale: .compact)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .frame(height: 40)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.controlSurface)
                            .overlay(Capsule().strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
                    )
                }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(
                        isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 720)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(Theme.Colors.snippetSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                        .strokeBorder(
                            Theme.Colors.panelEdgeHighlight(transparency: 0), lineWidth: 1)
                )
        )
        .onExitCommand(perform: onDismiss)
    }

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Template")
                    .font(.callout.weight(.medium))
                Spacer()
                placeholderMenu
            }
            TextEditor(text: $text, selection: $selection)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.sm)
                .frame(height: Theme.Size.snippetEditorTextHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.Colors.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )
                .focused($isTemplateFocused)
                .accessibilityLabel("Snippet template")
                .accessibilityHint("Enter the text Tinycast expands.")
        }
    }

    private var resolvedSymbol: String { iconSymbol ?? "curlybraces" }

    private var iconField: some View {
        Button { showingIconPicker = true } label: {
            HStack(spacing: Theme.Spacing.sm) {
                    SnippetIconGlyph(value: resolvedSymbol, size: 15)
                SymbolImage(name: "chevron.down", size: 9)
            }
            .frame(width: 52, height: Theme.Size.snippetControlHeight)
            .contentShape(Rectangle())
            .background(isIconHovered ? Theme.Colors.rowHover : Color.clear)
            .onHover { isIconHovered = $0 }
        }
        .buttonStyle(.plain)
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                SnippetIconPicker(selection: $iconSymbol) {
                    showingIconPicker = false
                }
            }
    }

    private var nameAndIconField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Name & Icon")
                .font(.callout.weight(.medium))
            HStack(spacing: 0) {
                TextField("Snippet name", text: $name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(height: Theme.Size.snippetControlHeight)
                Rectangle()
                    .fill(Theme.Colors.cardStroke)
                    .frame(width: 1, height: Theme.Size.snippetControlHeight - Theme.Spacing.md)
                iconField
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
            )
            .accessibilityElement(children: .contain)
            .accessibilityHint("Required name and optional custom icon.")
        }
    }

    /// Every placeholder the engine understands; parameters are in docs/features/snippets.md.
    private var placeholderMenu: some View {
        Menu("Insert…") {
            Section("Text") {
                placeholderItem("{cursor}")
                placeholderItem("{clipboard}")
                placeholderItem("{selection}")
                placeholderItem("{uuid}")
            }
            Section("Date & Time") {
                placeholderItem("{date}")
                placeholderItem("{time}")
                placeholderItem("{datetime}")
                placeholderItem("{day}")
            }
            Section("Arguments") {
                placeholderItem("{argument name=\"Name\"}")
            }
            Section("Snippets") {
                placeholderItem("{snippet name=\"Name\"}")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Insert a placeholder")
    }

    private func placeholderItem(_ token: String) -> some View {
        Button(token) { insert(token) }
    }

    /// Replaces the selection or lands at the caret; appends when there is no usable one.
    private func insert(_ token: String) {
        if let selection, case .selection(let range) = selection.indices,
            range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex
        {
            text.replaceSubrange(range, with: token)
        } else {
            text += token
        }
        // Those indices belong to the replaced string, so they must not survive the next insert.
        selection = nil
        isTemplateFocused = true
    }

    private func field(
        title: String, placeholder: String, text: Binding<String>, hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.callout.weight(.medium))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: Theme.Size.snippetControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
                )
                .accessibilityLabel("Snippet \(title.lowercased())")
                .accessibilityHint(hint)
        }
    }

    private func optionToggle(
        _ title: String, isOn: Binding<Bool>, detail: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
    }

    private var draft: Snippet {
        Snippet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            iconSymbol: iconSymbol,
            text: text,
            keyword: trimmedOrNil(keyword),
            isEnabled: isEnabled,
            showsConfirmation: showsConfirmation)
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                // Saving keeps the revision, so an edit in between conflicts, not clobbers.
                if var updated = record {
                    updated.snippet = draft
                    try await store.save(updated)
                } else {
                    try await store.create(draft)
                }
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct SnippetIconGlyph: View {
    let value: String
    let size: CGFloat

    var body: some View {
        if NSImage(systemSymbolName: value, accessibilityDescription: nil) != nil {
            SymbolImage(name: value, size: size)
        } else {
            Text(value)
                .font(.system(size: size))
        }
    }
}

private struct SnippetIconPicker: View {
    @Binding var selection: String?
    let onDone: () -> Void
    @Environment(EmojiIndex.self) private var emojiIndex
    @State private var mode: Mode
    @State private var icon: String
    @State private var emoji: String
    @State private var query = ""
    @State private var pastedEmoji = ""

    private enum Mode: String, CaseIterable {
        case icons, emoji
    }

    private static let symbols = [
        "curlybraces", "doc.text", "note.text", "text.quote", "envelope", "message",
        "calendar", "clock", "checklist", "star", "bookmark", "folder", "link", "globe",
        "terminal", "hammer", "wrench", "bolt", "gearshape", "lightbulb", "heart", "flag",
        "person", "person.2", "house", "cart", "creditcard", "cloud", "server.rack", "lock"
    ]

    init(selection: Binding<String?>, onDone: @escaping () -> Void) {
        _selection = selection
        self.onDone = onDone
        let value = selection.wrappedValue
        let isSymbol = value.map { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? true
        _mode = State(initialValue: isSymbol ? .icons : .emoji)
        _icon = State(initialValue: isSymbol ? (value ?? "curlybraces") : "curlybraces")
        _emoji = State(initialValue: isSymbol ? "💻" : (value ?? "💻"))
    }

    private var filteredSymbols: [String] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Self.symbols }
        return Self.symbols.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var emojis: [String] {
        let catalog = emojiIndex.entries.map(\.glyph)
        return Array((catalog.isEmpty ? Self.fallbackEmojis : catalog).prefix(80))
    }

    private static let fallbackEmojis = [
        "💻", "🛠️", "🚀", "🤖", "✨", "⚡", "🌐", "📱", "🖥️", "⌨️", "⚙️", "🗄️",
        "☁️", "📦", "📚", "🧪", "🔒", "🎮", "🎵", "🎬", "🖼️", "🛍️", "🔥", "💡",
        "🧩", "📊", "🧠", "🦄", "🐙", "🌱"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Choose snippet icon")
                .font(.title2.weight(.bold))
            Text("Pick an SF Symbol or use an emoji.")
                .foregroundStyle(.secondary)
            Picker("Icon type", selection: $mode) {
                Text("Icons").tag(Mode.icons)
                Text("Emoji").tag(Mode.emoji)
            }
            .pickerStyle(.segmented)
            if mode == .icons { iconPicker } else { emojiPicker }
            HStack {
                Spacer()
                Button("Cancel", action: onDone)
                Button("Save icon", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            TextField("Search SF Symbols", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(height: Theme.Size.snippetControlHeight)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: Theme.Spacing.sm
            ) {
                ForEach(filteredSymbols, id: \.self) { symbol in
                    Button { icon = symbol } label: {
                        SymbolImage(name: symbol, size: 18)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                                    .fill(icon == symbol ? Theme.Colors.selection : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                }
            }
        }
    }

    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: Theme.Spacing.sm
            ) {
                ForEach(emojis, id: \.self) { value in
                    Button { emoji = value } label: {
                        Text(value)
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                                    .fill(emoji == value ? Theme.Colors.selection : Color.clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Or paste any emoji")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("Paste an emoji", text: $pastedEmoji)
                .textFieldStyle(.roundedBorder)
                .frame(height: Theme.Size.snippetControlHeight)
                .onChange(of: pastedEmoji) { _, value in
                    if let first = value.first { emoji = String(first) }
                }
        }
    }

    private func save() {
        selection = mode == .icons ? icon : emoji
        onDone()
    }
}
