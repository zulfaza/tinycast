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

    private var palette: ThemePalette {
        selectedAppearance == .dark ? draft.dark : draft.light
    }

    var body: some View {
        Section {
            Picker("Edit", selection: $selectedAppearance) {
                ForEach(ThemeEditorAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            TextField("Name", text: name)
            colorPicker("Panel background", keyPath: \ThemePalette.panelBackground)
            colorPicker("Primary text", keyPath: \ThemePalette.primaryText)
            colorPicker("Accent", keyPath: \ThemePalette.accent)
            colorPicker("Secondary text", keyPath: \ThemePalette.support.secondaryText)
            colorPicker("Success", keyPath: \ThemePalette.support.success)
            colorPicker("Destructive", keyPath: \ThemePalette.support.destructive)
            Toggle("Use a two-stop gradient", isOn: gradientEnabled)
            if palette.gradient != nil {
                ColorPicker("Gradient first", selection: gradientColorBinding(first: true))
                ColorPicker("Gradient second", selection: gradientColorBinding(first: false))
                Slider(value: gradientAngle, in: -180...180, step: 1) {
                    Text("Gradient angle")
                } minimumValueLabel: {
                    Text("-180°")
                } maximumValueLabel: {
                    Text("180°")
                }
                .accessibilityValue(Text("\(Int(gradientAngle.wrappedValue)) degrees"))
            }
        } header: {
            SettingsSectionHeader(.customThemesTheme)
        } footer: {
            Text("Theme changes apply to Tinycast surfaces immediately.")
        }
        Section {
            HStack {
                Button("Import…") { showingImporter = true }
                Button("Export…") { prepareExport() }
                Spacer()
                Button("Reset", role: .destructive) {
                    themes.reset()
                    draft = .defaults
                }
                if let importError {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.destructive)
                }
            }
        } header: {
            Text("Portable theme")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importTheme)
        .fileExporter(
            isPresented: $showingExporter,
            document: $exportDocument,
            contentType: .json,
            defaultFilename: "Tinycast Theme.tinycast-theme",
            onCompletion: exportFinished)
        .onAppear { draft = themes.editableTheme }
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
            get: { palette.gradient.map(Self.displayAngle) ?? 0 },
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
