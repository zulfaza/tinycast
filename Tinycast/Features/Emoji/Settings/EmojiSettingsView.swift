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
                // A hand per tone, quicker to scan than a dropdown of tone names.
                Picker(selection: $settings.emojiSkinTone) {
                    ForEach(EmojiSkinTone.allCases) { tone in
                        Text(tone.sample).tag(tone)
                    }
                } label: {
                    SettingsRowTitle(.emojiAppearance, "Emoji Skin Tone")
                }
                .pickerStyle(.segmented)
            } header: {
                SettingsSectionHeader(.emojiAppearance)
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
                TextField("😀", text: $glyph)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Keyword") {
                TextField("for example, party", text: $keyword)
                    .textFieldStyle(.roundedBorder)
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
                    Text(record.value)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") { store.remove(record) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Remove keyword \(record.value)")
                }
            }
        } header: {
            Text("Search Keywords")
        } footer: {
            Text("Add words that should find an emoji in the picker.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
