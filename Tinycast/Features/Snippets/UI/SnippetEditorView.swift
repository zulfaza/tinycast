import AppKit
import SwiftUI

enum SnippetEditorState: Sendable {
    case create(Snippet)
    case edit(StoredSnippet)

    var snippet: Snippet {
        switch self {
        case .create(let snippet): snippet
        case .edit(let record): record.snippet
        }
    }

    var isEditing: Bool {
        switch self {
        case .create: false
        case .edit: true
        }
    }
}

struct SnippetEditorView: View {
    let state: SnippetEditorState
    let metrics: InterfaceMetrics

    let onDismiss: () -> Void
    @Environment(SnippetsStore.self) private var store
    @FocusState private var isTemplateFocused: Bool
    @State private var name: String
    @State private var keyword: String
    @State private var tags: String
    @State private var text: String
    @State private var selection: TextSelection?
    @State private var isEnabled: Bool
    @State private var showsConfirmation: Bool
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(state: SnippetEditorState, metrics: InterfaceMetrics, onDismiss: @escaping () -> Void) {
        self.state = state
        self.metrics = metrics
        self.onDismiss = onDismiss
        let snippet = state.snippet
        _name = State(initialValue: snippet.name)
        _keyword = State(initialValue: snippet.keyword ?? "")
        _tags = State(initialValue: snippet.tags.joined(separator: ", "))
        _text = State(initialValue: snippet.text)
        _isEnabled = State(initialValue: snippet.isEnabled)
        _showsConfirmation = State(initialValue: snippet.showsConfirmation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HStack(alignment: .top, spacing: metrics.spacing.xxl) {
                templateColumn
                metadataColumn
            }
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .padding(.horizontal, metrics.spacing.xxl)
        .padding(.vertical, metrics.spacing.xl)
        .frame(width: metrics.size.panelWidth, height: metrics.size.panelHeight)
        .environment(\.metrics, metrics)
        .background(Theme.Colors.panelScrim)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: metrics.radius.panel))
        .background(
            SnippetEditorEventMonitor(
                onEscape: onDismiss))
        .onExitCommand(perform: onDismiss)
    }

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(metrics.typography.headerIcon)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: metrics.size.headerIconSlot, height: metrics.size.headerHeight)
            }
            .buttonStyle(.plain)
            .help("Cancel")
            .accessibilityLabel("Cancel")
            Spacer()
        }
        .frame(height: metrics.size.headerHeight)
    }

    private var templateColumn: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            HStack {
                Text("Template")
                    .font(metrics.typography.sectionHeader)
                Spacer()
                placeholderMenu
            }
            templateEditor
            Text("Use {dynamic placeholders} for clipboard, dates, and arguments.")
                .font(metrics.typography.disclosure)
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var templateEditor: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text, selection: $selection)
                .font(metrics.typography.code)
                .scrollContentBackground(.hidden)
                .padding(metrics.spacing.sm)
                .frame(maxHeight: .infinity)
                .focused($isTemplateFocused)
                .accessibilityLabel("Snippet template")
                .accessibilityHint("Enter the text Tinycast expands.")
            Divider()
                .overlay(Theme.Colors.separator)
            formattingToolbar
                .padding(.horizontal, metrics.spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Theme.Colors.controlSurface,
            in: RoundedRectangle(cornerRadius: metrics.radius.row))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radius.row)
                .strokeBorder(Theme.Colors.cardStroke)
        }
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.row))
    }

    private var formattingToolbar: some View {
        HStack(spacing: metrics.spacing.sm) {
            formattingButton("bold", title: "Bold") { wrapSelection(with: "**") }
            formattingButton("italic", title: "Italic") { wrapSelection(with: "*") }
            formattingButton("strikethrough", title: "Strikethrough") {
                wrapSelection(with: "~~")
            }
            formattingButton("link", title: "Link") { insertLink() }
            Spacer(minLength: 0)
        }
        .frame(height: metrics.size.menuButton)
    }

    private func formattingButton(
        _ systemImage: String, title: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(metrics.typography.menuIcon)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: metrics.size.menuButton, height: metrics.size.menuButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

    private var metadataColumn: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.lg) {
            field(title: "Name", placeholder: "Snippet name", text: $name,
                hint: "Required. Shown in the library and launcher.")
            field(title: "Keyword", placeholder: "Optional, for example !notes", text: $keyword,
                hint: "Optional. Type this to expand the snippet.")
            field(title: "Tags", placeholder: "Optional, comma-separated", text: $tags,
                hint: "Optional. Filter browser results with #tag.")
            Divider().overlay(Theme.Colors.separator)
            optionToggle("Enabled", isOn: $isEnabled, detail: "Disabled snippets cannot be expanded.")
            optionToggle("Show confirmation", isOn: $showsConfirmation,
                detail: "Confirm on screen after this snippet is inserted.")
            if let errorMessage {
                Text(errorMessage)
                    .font(metrics.typography.disclosure)
                    .foregroundStyle(Theme.Colors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        HStack {
            Label {
                Text(state.isEditing ? "Edit Snippet" : "Create Snippet")
            } icon: {
                Image(systemName: "doc.text")
                    .foregroundStyle(Theme.Colors.primaryAction)
            }
            .font(metrics.typography.bar)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, metrics.spacing.lg)
            .frame(height: metrics.size.dialogButtonHeight)
            .background(Theme.Colors.controlSurface, in: Capsule())
            Spacer()
            Button("Save Snippet", action: save)
                .buttonStyle(.modalAction(.primary, fillsWidth: false))
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(height: metrics.size.bottomBarHeight)
    }

    /// Every placeholder the engine understands; parameters are in docs/features/snippets.md.
    private var placeholderMenu: some View {
        Menu("Insert…") {
            Section("Text") {
                placeholderItem("{cursor}")
                placeholderItem("{clipboard}")
                placeholderItem("{clipboard offset=1}")
                placeholderItem("{selection}")
                placeholderItem("{uuid}")
            }
            Section("Date & Time") {
                placeholderItem("{date}")
                placeholderItem("{time}")
                placeholderItem("{datetime}")
                placeholderItem("{day}")
                placeholderItem("{date format=\"yyyy-MM-dd\"}")
                placeholderItem("{date locale=\"fr-FR\"}")
                placeholderItem("{time offset=\"+3h +30m\"}")
            }
            Section("Arguments") {
                placeholderItem("{argument}")
                placeholderItem("{argument name=\"Name\"}")
                placeholderItem("{argument default=\"Default\"}")
                placeholderItem("{argument options=\"One, Two\"}")
            }
            Section("Snippets") {
                placeholderItem("{snippet:Name}")
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

    /// Replaces one selection and leaves the editor selection at the inserted text.
    private func insert(_ token: String) {
        replaceSelection(with: token, range: singleSelectionRange)
    }

    private func wrapSelection(with marker: String) {
        let range = singleSelectionRange
        let selected = range.map { String(text[$0]) } ?? ""
        let replacement = marker + selected + marker
        replaceSelection(
            with: replacement, range: range,
            caretOffset: range?.isEmpty == true ? marker.count : nil)
    }

    private func insertLink() {
        let range = singleSelectionRange
        let selected = range.map { String(text[$0]) } ?? "text"
        let replacement = "[\(selected)](url)"
        replaceSelection(
            with: replacement, range: range,
            selectionOffset: range?.isEmpty == true ? 1..<1 + selected.count : nil)
    }

    private var singleSelectionRange: Range<String.Index>? {
        guard let selection, case .selection(let range) = selection.indices,
            range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex
        else { return nil }
        return range
    }

    private func replaceSelection(
        with replacement: String, range: Range<String.Index>?, caretOffset: Int? = nil,
        selectionOffset: Range<Int>? = nil
    ) {
        let offset = range.map { text.distance(from: text.startIndex, to: $0.lowerBound) }
            ?? text.count
        if let range {
            text.replaceSubrange(range, with: replacement)
        } else {
            text += replacement
        }
        let insertedStart = text.index(text.startIndex, offsetBy: offset)
        if let selectionOffset {
            let lower = text.index(insertedStart, offsetBy: selectionOffset.lowerBound)
            let upper = text.index(insertedStart, offsetBy: selectionOffset.upperBound)
            selection = TextSelection(range: lower..<upper)
        } else {
            let insertionPoint = text.index(
                insertedStart, offsetBy: caretOffset ?? replacement.count)
            selection = TextSelection(insertionPoint: insertionPoint)
        }
        isTemplateFocused = true
    }

    private func field(
        title: String, placeholder: String, text: Binding<String>, hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text(title)
                .font(metrics.typography.disclosure)
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(metrics.typography.rowTrailing)
                .padding(.horizontal, metrics.spacing.lg)
                .frame(height: metrics.size.dialogButtonHeight)
                .background(
                    Theme.Colors.controlSurface,
                    in: RoundedRectangle(cornerRadius: metrics.radius.row))
                .accessibilityLabel("Snippet \(title.lowercased())")
                .accessibilityHint(hint)
        }
    }

    private func optionToggle(
        _ title: String, isOn: Binding<Bool>, detail: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(title)
                Text(detail)
                    .font(metrics.typography.disclosure)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
    }

    private var draft: Snippet {
        Snippet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            text: text,
            keyword: trimmedOrNil(keyword),
            tags: tags.split(separator: ",").map(String.init),
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
                switch state {
                case .create:
                    try await store.create(draft)
                case .edit(var record):
                    record.snippet = draft
                    try await store.save(record)
                }
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SnippetEditorEventMonitor: NSViewRepresentable {
    let onEscape: () -> Void

    @MainActor
    final class Coordinator {
        var monitor: Any?

        isolated deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak view] event in
            guard let window = view?.window, event.window === window else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53, modifiers.isEmpty {
                onEscape()
                return nil
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
            coordinator.monitor = nil
        }
    }
}
