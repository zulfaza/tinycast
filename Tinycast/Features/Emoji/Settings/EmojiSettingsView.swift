import SwiftUI

struct EmojiSettingsView: View {
    @Environment(AppSettings.self) private var settings
    let keywordStore: EmojiKeywordStore?
    let index: EmojiIndex?

    init(keywordStore: EmojiKeywordStore? = nil, index: EmojiIndex? = nil) {
        self.keywordStore = keywordStore
        self.index = index
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureCommandsSection(owner: .emoji, anchor: .emojiCommands)

            Section {
                EmojiColumnCountPicker(selection: $settings.emojiGridColumns)
            } header: {
                SettingsSectionHeader(.emojiAppearance)
            }

            Section {
                // A hand per tone, quicker to scan than a dropdown of tone names.
                Picker(selection: $settings.emojiSkinTone) {
                    ForEach(EmojiSkinTone.allCases) { tone in
                        Text(tone.sample).tag(tone)
                    }
                } label: {
                    SettingsRowTitle(.emojiAppearance, "Emoji Skin Tone")
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Applied when an emoji supports skin tones; pastes use it too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let keywordStore {
                EmojiKeywordSettingsSection(store: keywordStore, index: index)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.emoji)
    }
}

private struct EmojiKeywordSettingsSection: View {
    let store: EmojiKeywordStore
    let index: EmojiIndex?
    @State private var glyph = ""
    @State private var keyword = ""

    var body: some View {
        Section {
            LabeledContent("Emoji") {
                TextField("😀", text: $glyph).textFieldStyle(.roundedBorder)
            }
            LabeledContent("Keyword") {
                TextField("for example, party", text: $keyword).textFieldStyle(.roundedBorder)
            }
            Button("Add Search Keyword") {
                let candidateGlyph = glyph.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let index, let entry = index.entry(for: candidateGlyph),
                    store.add(keyword: keyword, for: entry)
                else { return }
                glyph = ""
                keyword = ""
            }
            .disabled(glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(store.records) { record in
                HStack {
                    Text(record.glyph)
                    Text(record.value).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") { store.remove(record) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Search Keywords")
        }
    }
}

/// Five previews make the picker's starting density legible before the user opens it.
private struct EmojiColumnCountPicker: View {
    @Binding var selection: EmojiGridColumns

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsRowTitle(.emojiAppearance, "Column Count")

            HStack(spacing: Theme.Spacing.xl) {
                ForEach(EmojiGridColumns.allCases) { columns in
                    option(columns)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func option(_ columns: EmojiGridColumns) -> some View {
        let isSelected = selection == columns
        return Button {
            selection = columns
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                EmojiColumnCountPreview(columns: columns.rawValue, isSelected: isSelected)
                Text(columns.rawValue, format: .number)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(columns.rawValue) columns")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct EmojiColumnCountPreview: View {
    let columns: Int
    let isSelected: Bool
    var body: some View {
        Text("\(columns)")
    }
}

/// Dots share one lattice, so horizontal and vertical runs meet on the exact same point.
private struct EmojiGridDots: Shape {
    let columns: Int

    private static let pointsPerCell = 4
    /// Match the outline's raster weight; subpixel circles render visibly fainter at the same alpha.
    private static let dotDiameter = Theme.Size.hairline

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let subdivisions = columns * Self.pointsPerCell
        guard subdivisions > 0 else { return path }
        let horizontalStep = rect.width / CGFloat(subdivisions)
        let verticalStep = rect.height / CGFloat(subdivisions)
        let radius = Self.dotDiameter / 2

        for row in 0...subdivisions {
            for column in 0...subdivisions {
                let onVertical =
                    column.isMultiple(of: Self.pointsPerCell)
                    && column > 0 && column < subdivisions
                let onHorizontal =
                    row.isMultiple(of: Self.pointsPerCell)
                    && row > 0 && row < subdivisions
                guard onVertical || onHorizontal else { continue }
                let center = CGPoint(
                    x: rect.minX + CGFloat(column) * horizontalStep,
                    y: rect.minY + CGFloat(row) * verticalStep)
                path.addEllipse(
                    in: CGRect(
                        x: center.x - radius, y: center.y - radius,
                        width: Self.dotDiameter, height: Self.dotDiameter))
            }
        }
        return path
    }
}
