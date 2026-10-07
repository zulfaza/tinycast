import SwiftUI

/// The category picker shared by the Backup pane and onboarding.
struct RaycastImportSelection: View {
    @Binding var selection: RaycastImportOptions

    private struct Category: Identifiable {
        let option: RaycastImportOptions
        let symbol: String
        let label: String
        let tint: TileTint
        var id: Int { option.rawValue }
    }

    private static let categories: [Category] = [
        .init(option: .shortcuts, symbol: "command", label: "Shortcuts", tint: .gray),
        .init(option: .favorites, symbol: "star.fill", label: "Favorites", tint: .yellow),
        .init(
            option: .aliases, symbol: "character.cursor.ibeam", label: "Aliases", tint: .teal),
        .init(
            option: .emojiSkinTone, symbol: "face.smiling.inverse", label: "Emoji skin tone",
            tint: .yellow),
        .init(option: .launchAtLogin, symbol: "power", label: "Launch at login", tint: .gray),
        .init(
            option: .menuBarVisibility, symbol: "menubar.rectangle", label: "Menu-bar icon",
            tint: .gray),
        .init(
            option: .clipboardHistory, symbol: "doc.on.clipboard.fill", label: "Clipboard history",
            tint: .brown),
        .init(option: .snippets, symbol: "curlybraces", label: "Snippets", tint: .cyan),
        .init(option: .quicklinks, symbol: Quicklink.sfSymbol, label: "Quicklinks", tint: .blue),
        .init(
            option: .popToRoot, symbol: "arrow.uturn.backward", label: "Pop to root", tint: .gray),
        .init(option: .compactMode, symbol: "macwindow", label: "Compact mode", tint: .pink)
    ]

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md, alignment: .leading), count: 3)

    private func included(_ option: RaycastImportOptions) -> Binding<Bool> {
        Binding(
            get: { selection.contains(option) },
            set: { selection = $0 ? selection.union(option) : selection.subtracting(option) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Self.categories) { category in
                    Toggle(isOn: included(category.option)) {
                        HStack(spacing: Theme.Spacing.sm) {
                            SettingsSymbolTile(symbol: category.symbol, tint: category.tint)
                            Text(category.label).lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Button(selection == .all ? "Deselect All" : "Select All") {
                selection = selection == .all ? [] : .all
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
