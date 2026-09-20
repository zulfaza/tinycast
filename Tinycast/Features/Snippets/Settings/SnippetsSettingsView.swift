import AppKit
import SwiftUI

struct SnippetsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(SnippetsStore.self) private var snippetsStore
    @Environment(AppSettings.self) private var settings

    @State private var pendingDeletion: StoredSnippet?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .snippetsSnippets,
                enableTitle: "Enable snippets",
                enableSubtitle:
                    "Reusable Markdown templates, expanded from the launcher or a typed keyword.",
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
