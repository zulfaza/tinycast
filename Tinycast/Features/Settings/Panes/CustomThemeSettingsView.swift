import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// General Appearance's editor for the two palettes carried by a portable theme file.
struct CustomThemeSettingsView: View {
    @Environment(CustomThemeStore.self) private var themes
    @State private var draft = CustomTheme.defaults
    @State private var selectedAppearance = ThemeEditorAppearance.light
    @State private var showingImporter = false
    @State private var exportDocument: CustomThemeFileDocument?
    @State private var showingExporter = false
    @State private var importError: String?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        selectedAppearance == .dark ? draft.dark : draft.light
    }

    var body: some View {
        Form {
            Section {
                ThemePreview(palette: palette)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                Picker("Appearance", selection: $selectedAppearance) {
                    ForEach(ThemeEditorAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent {
                    TextField("Name", text: name, prompt: Text("Untitled Theme"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                } label: {
                    SettingsRowTitle(.customThemesTheme, "Name")
                }
            } header: {
                SettingsSectionHeader(.customThemesTheme)
            } footer: {
                Text("Light and Dark are separate palettes; Tinycast follows the Mac's appearance.")
            }

            Section {
                colorPicker("Panel", keyPath: \ThemePalette.panelBackground)
                Toggle("Gradient", isOn: gradientEnabled)
                if palette.gradient != nil {
                    ColorPicker("Start", selection: gradientColorBinding(first: true))
                    ColorPicker("End", selection: gradientColorBinding(first: false))
                    LabeledContent("Angle") {
                        HStack(spacing: Theme.Spacing.md) {
                            Slider(value: gradientAngle, in: -180...180, step: 1)
                                .labelsHidden()
                            Text("\(Int(gradientAngle.wrappedValue))°")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(minWidth: Theme.Spacing.xl * 2, alignment: .trailing)
                        }
                    }
                    .accessibilityValue(Text("\(Int(gradientAngle.wrappedValue)) degrees"))
                }
            } header: {
                SettingsSectionHeader(.customThemesBackground)
            }

            Section {
                colorPicker("Primary", keyPath: \ThemePalette.primaryText)
                colorPicker("Secondary", keyPath: \ThemePalette.support.secondaryText)
            } header: {
                SettingsSectionHeader(.customThemesText)
            }

            Section {
                colorPicker("Accent", keyPath: \ThemePalette.accent)
                colorPicker("Success", keyPath: \ThemePalette.support.success)
                colorPicker("Destructive", keyPath: \ThemePalette.support.destructive)
            } header: {
                SettingsSectionHeader(.customThemesAccents)
            } footer: {
                Text("Accent also tints the selected row.")
            }

            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button("Import…") { showingImporter = true }
                        Button("Export…") { prepareExport() }
                    }
                } label: {
                    Text("Share")
                    Text("A .tinycast-theme file holds both palettes.")
                }
                LabeledContent {
                    Button("Reset", role: .destructive) {
                        themes.reset()
                        draft = .defaults
                        importError = nil
                    }
                } label: {
                    Text("Restore Defaults")
                    Text("Removes the custom theme.")
                }
            } header: {
                SettingsSectionHeader(.customThemesFile)
            } footer: {
                if let importError {
                    Label(importError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.destructive)
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importTheme)
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Tinycast Theme.tinycast-theme",
            onCompletion: exportFinished)
        .onAppear {
            draft = themes.editableTheme
            selectedAppearance = colorScheme == .dark ? .dark : .light
        }
        .settingsScrollTarget(.customThemes)
    }

    private var name: Binding<String> {
        Binding(
            get: { draft.name },
            set: {
                draft.name = $0
                applyDraft()
            })
    }

    private var gradientEnabled: Binding<Bool> {
        Binding(
            get: { palette.gradient != nil },
            set: { enabled in
                var updated = palette
                if enabled {
                    updated.gradient = ThemeGradient(
                        first: palette.panelBackground, second: palette.panelBackground, angle: 0)
                } else {
                    updated.gradient = nil
                }
                update(updated)
            })
    }

    private var gradientAngle: Binding<Double> {
        Binding(
            get: { palette.gradient.map { Self.displayAngle($0.angle) } ?? 0 },
            set: { angle in
                guard let gradient = palette.gradient,
                    let updatedGradient = ThemeGradient(
                        first: gradient.first, second: gradient.second, angle: angle)
                else { return }
                var updated = palette
                updated.gradient = updatedGradient
                update(updated)
            })
    }

    private func colorPicker(
        _ title: String,
        keyPath: WritableKeyPath<ThemePalette, ThemeColor>
    ) -> some View {
        ColorPicker(title, selection: colorBinding(keyPath))
    }

    private func colorBinding(
        _ keyPath: WritableKeyPath<ThemePalette, ThemeColor>
    ) -> Binding<Color> {
        Binding(
            get: { palette[keyPath: keyPath].swiftUIColor },
            set: { color in
                guard let resolved = NSColor(color).usingColorSpace(.sRGB),
                    let themeColor = ThemeColor(
                        red: Double(resolved.redComponent),
                        green: Double(resolved.greenComponent),
                        blue: Double(resolved.blueComponent),
                        alpha: Double(resolved.alphaComponent))
                else { return }
                var updated = palette
                updated[keyPath: keyPath] = themeColor
                update(updated)
            })
    }

    private func gradientColorBinding(first: Bool) -> Binding<Color> {
        Binding(
            get: {
                let color = first ? palette.gradient?.first : palette.gradient?.second
                return (color ?? palette.panelBackground).swiftUIColor
            },
            set: { color in
                guard let gradient = palette.gradient,
                    let resolved = NSColor(color).usingColorSpace(.sRGB),
                    let themeColor = ThemeColor(
                        red: Double(resolved.redComponent),
                        green: Double(resolved.greenComponent),
                        blue: Double(resolved.blueComponent),
                        alpha: Double(resolved.alphaComponent)),
                    let updatedGradient = ThemeGradient(
                        first: first ? themeColor : gradient.first,
                        second: first ? gradient.second : themeColor,
                        angle: gradient.angle)
                else { return }
                var updated = palette
                updated.gradient = updatedGradient
                update(updated)
            })
    }

    private func update(_ palette: ThemePalette) {
        if selectedAppearance == .dark {
            draft.dark = palette
        } else {
            draft.light = palette
        }
        applyDraft()
    }

    private func applyDraft() {
        do {
            try themes.preview(draft)
            importError = nil
        } catch {
            draft = themes.editableTheme
            importError = error.localizedDescription
        }
    }

    private func prepareExport() {
        do {
            exportDocument = try CustomThemeFileDocument(data: themes.exportTheme())
            showingExporter = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importTheme(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try themes.importTheme(from: Data(contentsOf: url))
            draft = themes.editableTheme
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func exportFinished(_ result: Result<URL, Error>) {
        if case .failure(let error) = result { importError = error.localizedDescription }
    }

    private static func displayAngle(_ angle: Double) -> Double {
        angle > 180 ? angle - 360 : angle
    }
}

/// The palette in miniature, drawn from the draft so every edit shows before it is anywhere else.
private struct ThemePreview: View {
    let palette: ThemePalette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous)
        let primary = palette.primaryText.swiftUIColor
        let secondary = palette.support.secondaryText.swiftUIColor
        let accent = palette.accent.swiftUIColor
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "magnifyingglass")
                Text("Search for apps and commands…")
                Spacer(minLength: 0)
            }
            .foregroundStyle(secondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            Rectangle()
                .fill(secondary.opacity(Theme.Size.themePreviewHairlineAlpha))
                .frame(height: Theme.Size.hairline)
            row("curlybraces", "Search Snippets", detail: "Command", selected: true)
            row("doc.on.clipboard", "Clipboard History", detail: "Command", selected: false)
            HStack(spacing: Theme.Spacing.md) {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(palette.support.success.swiftUIColor)
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(palette.support.destructive.swiftUIColor)
                Spacer(minLength: 0)
                Text("↵")
                    .foregroundStyle(primary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .background(
                        accent.opacity(Theme.Size.themePreviewSelectionAlpha),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
            }
            .font(.caption)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.md)
        .frame(width: Theme.Size.themePreviewWidth)
        .background(background, in: shape)
        .overlay(shape.strokeBorder(secondary.opacity(Theme.Size.themePreviewHairlineAlpha), lineWidth: Theme.Size.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Theme preview")
    }

    private func row(_ symbol: String, _ title: String, detail: String, selected: Bool) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(
                    selected
                        ? palette.accent.swiftUIColor : palette.support.secondaryText.swiftUIColor)
                .frame(width: Theme.Size.themePreviewRowIcon, height: Theme.Size.themePreviewRowIcon)
            Text(title).foregroundStyle(palette.primaryText.swiftUIColor)
            Spacer(minLength: 0)
            Text(detail)
                .font(.caption)
                .foregroundStyle(palette.support.secondaryText.swiftUIColor)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            selected
                ? palette.accent.swiftUIColor.opacity(Theme.Size.themePreviewSelectionAlpha) : .clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }

    /// The same angle-to-points mapping `Theme.Colors.panelSurface` paints the real panel with.
    private var background: AnyShapeStyle {
        guard let gradient = palette.gradient else {
            return AnyShapeStyle(palette.panelBackground.swiftUIColor)
        }
        let radians = gradient.angle * .pi / 180
        let dx = cos(radians) / 2
        let dy = sin(radians) / 2
        return AnyShapeStyle(
            LinearGradient(
                colors: [gradient.first.swiftUIColor, gradient.second.swiftUIColor],
                startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)))
    }
}

private enum ThemeEditorAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String { rawValue.capitalized }
}

private struct CustomThemeFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) throws {
        _ = try CustomThemeDocument.decode(data)
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CustomThemeFileError.invalidFormat
        }
        try self.init(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private extension ThemeColor {
    var swiftUIColor: Color {
        Color(
            .sRGB, red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue),
            opacity: CGFloat(alpha))
    }
}
