import AppKit
import SwiftUI

/// Small editor surfaces for clipboard actions that need user input or a destination.
@MainActor
final class ClipboardEditorWindowController {
    private let core: AppCore
    private let window: AppWindowController

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: "Clipboard Entry", contentSize: CGSize(width: 480, height: 260),
            resizable: false, activation: core.activationPolicy)
    }

    func rename(_ item: ClipboardItem) {
        show { ClipboardRenameView(item: item) { [weak self] name in
            self?.core.clipboardStore.rename(item, to: name)
            self?.window.close()
        } }
    }

    func saveAsFile(_ item: ClipboardItem) {
        show { ClipboardSaveFileView(item: item) { [weak self] in
            self?.window.close()
        } }
    }

    private func show<Content: View>(@ViewBuilder content: () -> Content) {
        window.show { content().environment(core).environment(core.settings) }
    }
}

private struct ClipboardRenameView: View {
    let item: ClipboardItem
    let onSave: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(item: ClipboardItem, onSave: @escaping (String?) -> Void) {
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: item.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Rename Entry").font(.title2.weight(.bold))
            TextField("Optional label", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { onSave(name) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
    }
}

private struct ClipboardSaveFileView: View {
    let item: ClipboardItem
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Save as File").font(.title2.weight(.bold))
            Text("Choose where to save this text entry.").foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Choose…", action: choose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
    }

    private func choose() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Clipboard.txt"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url, let text = item.text else {
                return
            }
            try? text.write(to: url, atomically: true, encoding: .utf8)
            onDone()
        }
    }
}
