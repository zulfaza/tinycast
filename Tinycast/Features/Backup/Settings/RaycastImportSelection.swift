import SwiftUI

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
        .init(option: .shortcuts, symbol: "command", label: String(localized: "Shortcuts"), tint: .gray),
        .init(option: .favorites, symbol: "star.fill", label: String(localized: "Favorites"), tint: .yellow),
        .init(
            option: .aliases, symbol: "character.cursor.ibeam", label: String(localized: "Aliases"), tint: .teal),
        .init(
            option: .emojiSkinTone, symbol: "face.smiling.inverse", label: String(localized: "Emoji skin tone"),
            tint: .yellow),
        .init(option: .launchAtLogin, symbol: "power", label: String(localized: "Launch at login"), tint: .gray),
        .init(
            option: .menuBarVisibility, symbol: "menubar.rectangle", label: String(localized: "Menu-bar icon"),
            tint: .gray),
        .init(
            option: .clipboardHistory, symbol: "doc.on.clipboard.fill", label: String(localized: "Clipboard history"),
            tint: .brown),
        .init(option: .snippets, symbol: "curlybraces", label: String(localized: "Snippets"), tint: .cyan),
        .init(option: .quicklinks, symbol: Quicklink.sfSymbol, label: String(localized: "Quicklinks"), tint: .blue),
        .init(
            option: .popToRoot, symbol: "arrow.uturn.backward", label: String(localized: "Pop to root"), tint: .gray),
        .init(option: .compactMode, symbol: "macwindow", label: String(localized: "Compact mode"), tint: .pink)
    ]

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md, alignment: .leading), count: 2)

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
