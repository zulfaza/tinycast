import AppKit
import SwiftUI

struct SnippetsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(SnippetCoordinator.self) private var coordinator
    @Environment(SnippetsStore.self) private var snippetsStore
    @Environment(AppSettings.self) private var settings

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
                    set: { coordinator.setSnippetsEnabled($0) }),
                showsInLauncher: $settings.snippetsShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            if settings.snippetsEnabled, core.snippetListener.status == .needsAccessibility {
                Section {
                    LabeledContent {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                    } label: {
                        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .frame(width: SettingsListMetrics.iconSize)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text("Keyword expansion needs Accessibility access")
                                    .foregroundStyle(.orange)
                                Text("Launcher search still works.")
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                        onEdit: { coordinator.editSnippet(record) },
                        onDelete: { Task { await coordinator.deleteSnippet(id: record.id) } })
                }
            }

            LabeledContent {
                Button("Add…") { coordinator.editSnippet(nil) }
            } label: {
                SettingsRowTitle(.snippetsLibrary, "New Snippet")
                Text("Give the snippet a searchable name and an optional expansion keyword.")
            }

            LabeledContent {
                if settings.snippetsFolder != nil {
                    Button("Use Default", action: coordinator.resetSnippetsFolder)
                }
                Button("Choose…", action: coordinator.chooseSnippetsFolder)
                Button("Open Folder", action: coordinator.revealSnippetsInFinder)
                    .accessibilityHint("Reveals the snippets folder in Finder.")
            } label: {
                SettingsRowTitle(.snippetsLibrary, "Snippets Folder")
                Text((snippetsStore.snippetsDirectory.path as NSString).abbreviatingWithTildeInPath)
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
}

private struct SnippetSettingsRow: View {
    let record: StoredSnippet
    let canEdit: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: record.snippet.name, subtitle: metadata) {
            AppIconView(app: AppEntry(record))
                .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
        } trailing: {
            // A disabled snippet's shortcut fires into the funnel's refusal, so it dims too.
            ShortcutRecorder(action: .snippet(id: record.id))
                .settingsEnabled(record.snippet.isEnabled)

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
        else { return filename }
        return "\(keyword) · \(filename)"
    }
}
