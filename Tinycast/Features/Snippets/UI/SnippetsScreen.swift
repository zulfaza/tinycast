import SwiftUI

struct SnippetsScreen: PaletteScreen {
    let store: SnippetsStore
    let core: AppCore
    let vm: PaletteState

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    let openActions: () -> Void
    let openArgumentOptions: (String) -> Void

    var rows: [StoredSnippet] { store.browserRows(matching: vm.query) }

    private var defaultAction: SnippetDefaultAction { core.settings.snippetDefaultAction }

    var primaryActionTitle: String { defaultAction.menuTitle }

    private func record(at selection: Int) -> StoredSnippet? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let record = record(at: selection) else { return nil }
        return SnippetActionsMenu.content(
            record: record, defaultAction: defaultAction, core: core,
            canEdit: store.isWritable(record), userArguments: userArguments(for: record))
    }

    func activate(at selection: Int) {
        guard let record = record(at: selection) else { return }
        core.snippetCoordinator.performFromPalette(
            defaultAction, id: record.id, userArguments: userArguments(for: record))
    }

    func secondary(at selection: Int) -> Bool {
        guard let record = record(at: selection) else { return false }
        core.snippetCoordinator.performFromPalette(
            defaultAction.alternate, id: record.id, userArguments: userArguments(for: record))
        return true
    }

    private func userArguments(for record: StoredSnippet) -> [String: String] {
        SnippetArgumentsAccessory.values(for: record, coordinator: core.snippetCoordinator, vm: vm)
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if shortcut == .newItem {
            core.snippetCoordinator.editSnippet(nil)
            return true
        }
        guard let record = record(at: selection) else { return false }
        switch shortcut {
        case .edit:
            guard store.isWritable(record) else { return false }
            core.snippetCoordinator.editSnippet(record)
        case .pin:
            Task { await core.snippetCoordinator.toggleSnippetPinned(id: record.id) }
        case .showInFinder:
            core.snippetCoordinator.showSnippetInFinder(record)
        case .delete:
            Task { await core.snippetCoordinator.deleteSnippet(id: record.id) }
        default: return false
        }
        return true
    }

    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    ) -> PaletteHeaderAccessory? {
        SnippetArgumentsAccessory.make(
            snippet: record(at: selection), coordinator: core.snippetCoordinator, vm: vm,
            focus: focus, onOpenOptions: openArgumentOptions,
            onSubmit: { activate(at: selection) })
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(text: emptyMessage)
        } else {
            let selected = record(at: selection)
            HStack(spacing: 0) {
                SnippetsList(
                    results: rows, usage: store.usage, selectedID: selected?.id, scroll: scroll,
                    onSelect: { record in
                        vm.selection = rows.firstIndex(of: record) ?? 0
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { record in
                        if let index = rows.firstIndex(of: record) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                SnippetPreview(record: selected, usage: store.usage)
            }
        }
    }

    /// An empty library and an over-narrow filter are different problems with different answers.
    private var emptyMessage: String {
        if store.state == .loading { return String(localized: "Loading snippets…") }
        return store.snippets.contains(where: { $0.snippet.isEnabled })
            ? String(localized: "No matching snippets") : String(localized: "No snippets yet")
    }
}

@MainActor
enum SnippetActionsMenu {
    static func content(
        record: StoredSnippet, defaultAction: SnippetDefaultAction, core: AppCore, canEdit: Bool,
        userArguments: [String: String]
    ) -> PopoverMenuContent {
        let isPinned = record.snippet.isPinned
        var items = [
            item(defaultAction, shortcut: "↵", record: record, core: core, userArguments: userArguments),
            item(
                defaultAction.alternate, shortcut: "⌘↵", record: record, core: core,
                userArguments: userArguments),
        ]
        if canEdit {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Edit Snippet"), systemImage: "pencil", startsSection: true,
                    shortcut: "⌘E"
                ) {
                    core.snippetCoordinator.editSnippet(record)
                })
        }
        items += [
            PopoverMenuItem(
                title: String(localized: "Create Snippet"), systemImage: "plus", shortcut: "⌘N"
            ) {
                core.snippetCoordinator.editSnippet(nil)
            },
            PopoverMenuItem(
                title: isPinned ? String(localized: "Unpin Snippet") : String(localized: "Pin Snippet"),
                systemImage: isPinned ? "pin.slash" : "pin", shortcut: "⌘."
            ) {
                Task { await core.snippetCoordinator.toggleSnippetPinned(id: record.id) }
            },
            PopoverMenuItem(
                title: String(localized: "Show in Finder"), systemImage: "folder", startsSection: true,
                shortcut: "⌘F"
            ) {
                core.snippetCoordinator.showSnippetInFinder(record)
            },
            PopoverMenuItem(
                title: String(localized: "Delete Snippet"), systemImage: "trash", startsSection: true,
                shortcut: "⌃X", isDestructive: true
            ) {
                Task { await core.snippetCoordinator.deleteSnippet(id: record.id) }
            },
        ]
        return PopoverMenuContent(header: record.snippet.name, items: items)
    }

    private static func item(
        _ action: SnippetDefaultAction, shortcut: String, record: StoredSnippet, core: AppCore,
        userArguments: [String: String]
    ) -> PopoverMenuItem {
        PopoverMenuItem(title: action.menuTitle, systemImage: action.systemImage, shortcut: shortcut) {
            core.snippetCoordinator.performFromPalette(action, id: record.id, userArguments: userArguments)
        }
    }
}

extension SnippetDefaultAction {
    fileprivate var menuTitle: String {
        switch self {
        case .paste: String(localized: "Paste Snippet")
        case .copy: String(localized: "Copy Snippet")
        }
    }

    fileprivate var systemImage: String {
        switch self {
        case .paste: "text.quote"
        case .copy: "doc.on.doc"
        }
    }
}
