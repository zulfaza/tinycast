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

            expansion

            Group {
                FeatureCommandsSection(owner: .snippets, anchor: .snippetsCommands)
                library
                libraryNotices
            }
            .settingsEnabled(settings.snippetsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.snippets)
        // Presented from the pane, so the browser's Edit and Create rows can open it too.
        .sheet(item: $core.pendingSnippetEdit) { request in
            SnippetEditorSheet(record: request.record)
        }
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

    private var expansion: some View {
        @Bindable var settings = settings
        return Section {
            Picker("Trigger", selection: $settings.snippetsTriggerMode) {
                Text("Immediately").tag(SnippetExpansionTriggerMode.immediate)
                Text("After delimiter").tag(SnippetExpansionTriggerMode.delimiter)
            }
            if settings.snippetsTriggerMode == .delimiter {
                TextField("Delimiter (whitespace or literal)", text: $settings.snippetsDelimiter)
                Toggle("Keep delimiter", isOn: $settings.snippetsRetainsDelimiter)
            }
            Picker("Output", selection: $settings.snippetsOutput) {
                ForEach(SnippetExpansionOutput.allCases, id: \.rawValue) { output in
                    Text(output.title).tag(output)
                }
            }
            Picker("Injection delay", selection: $settings.snippetsInjectionDelay) {
                ForEach(SnippetInjectionDelay.allCases) { delay in
                    Text(delay.title).tag(delay)
                }
            }
            Toggle("Show completion feedback", isOn: $settings.snippetsCompletionFeedback)
            TextField(
                "Excluded app bundle IDs (comma-separated)",
                text: Binding(
                    get: { settings.snippetsExcludedApps.joined(separator: ", ") },
                    set: { settings.snippetsExcludedApps = $0.split(separator: ",").map(String.init) }))
            LabeledContent("Shared libraries") {
                HStack {
                    Button("Choose folders…", action: chooseSharedLibraries)
                    if !settings.snippetsSharedLibraries.isEmpty {
                        Button("Clear") { settings.snippetsSharedLibraries = [] }
                    }
                }
            }
            ForEach(settings.snippetsSharedLibraries, id: \.self) { directory in
                HStack {
                    Text(directory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Theme.Spacing.lg)
                    Button("Remove") {
                        settings.snippetsSharedLibraries.removeAll { $0 == directory }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove shared library (directory)")
                }
            }
        } header: {
            SettingsSectionHeader(.snippetsExpansion)
        } footer: {
            Text("Control when and where keyword expansion runs. Shared libraries stay read-only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chooseSharedLibraries() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            settings.snippetsSharedLibraries = panel.urls.map(\.path)
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
                        canEdit: snippetsStore.isWritable(record),
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

        // The editor reports its own failures, so this covers the ones with no sheet behind.
        if core.pendingSnippetEdit == nil, let operationError = snippetsStore.operationError {
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

struct SnippetEditRequest: Identifiable {
    let id = UUID()
    /// nil for a snippet that has no file yet.
    let record: StoredSnippet?
}

private struct SnippetSettingsRow: View {
    let record: StoredSnippet
    let canEdit: Bool
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
            .disabled(!canEdit)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .help("Delete Snippet")
            .accessibilityLabel("Delete \(record.snippet.name)")
            .disabled(!canEdit)
        }
    }

    private var metadata: String {
        let filename = record.fileURL.lastPathComponent
        guard let keyword = record.snippet.keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
            !keyword.isEmpty
        else {
            return metadataWithTags(filename: filename)
        }
        return metadataWithTags(filename: "\(keyword) · \(filename)")
    }

    private func metadataWithTags(filename: String) -> String {
        var parts = [filename]
        if !record.snippet.tags.isEmpty {
            parts.append(record.snippet.tags.map { "#\($0)" }.joined(separator: " "))
        }
        if !canEdit { parts.append("Read-only shared library") }
        return parts.joined(separator: " · ")
    }
}

private struct SnippetEditorSheet: View {
    /// nil while adding; otherwise the record whose file (and revision) the save targets.
    let record: StoredSnippet?

    @Environment(\.dismiss) private var dismiss
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

    init(record: StoredSnippet?) {
        self.record = record
        let snippet = record?.snippet
        _name = State(initialValue: snippet?.name ?? "")
        _keyword = State(initialValue: snippet?.keyword ?? "")
        _tags = State(initialValue: snippet?.tags.joined(separator: ", ") ?? "")
        _text = State(initialValue: snippet?.text ?? "")
        _isEnabled = State(initialValue: snippet?.isEnabled ?? true)
        _showsConfirmation = State(initialValue: snippet?.showsConfirmation ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(record == nil ? "Add Snippet" : "Edit Snippet")
                .font(.title2.weight(.bold))

            field(
                title: "Name", placeholder: "Email Sign-off", text: $name,
                hint: "Required. Shown in the library and launcher.")
            field(
                title: "Keyword", placeholder: "Optional, for example !notes", text: $keyword,
                hint: "Optional. Type this to expand the snippet.")
            field(
                title: "Tags", placeholder: "Optional, comma-separated", text: $tags,
                hint: "Optional. Filter browser results with #tag.")

            templateEditor

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                optionToggle(
                    "Enabled", isOn: $isEnabled,
                    detail: "Disabled snippets cannot be expanded.")
                optionToggle(
                    "Show confirmation", isOn: $showsConfirmation,
                    detail: "Confirm on screen after this snippet is inserted.")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth, height: 475)
        .background(
            SnippetEditorEventMonitor(
                onEscape: { dismiss() }))
        .onExitCommand(perform: dismiss.callAsFunction)
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
                .frame(height: Theme.Size.editorTextHeight)
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
                .textFieldStyle(.roundedBorder)
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
                if var updated = record {
                    updated.snippet = draft
                    try await store.save(updated)
                } else {
                    try await store.create(draft)
                }
                dismiss()
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
