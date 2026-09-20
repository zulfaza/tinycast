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
        Form {
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
                CustomThemePreview(palette: palette, appearance: selectedAppearance)
            } header: {
                Text("Preview")
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
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importTheme
        )
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Tinycast Theme.tinycast-theme",
            onCompletion: exportFinished
        )
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

private enum ThemeEditorAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }
}

private struct CustomThemePreview: View {
    let palette: ThemePalette
    let appearance: ThemeEditorAppearance

    private var primary: Color { palette.primaryText.swiftUIColor }
    private var secondary: Color { palette.support.secondaryText.swiftUIColor }
    private var accent: Color { palette.accent.swiftUIColor }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous)
        VStack(spacing: 0) {
            header
            separator
            VStack(spacing: Theme.Spacing.xxs) {
                row(symbol: "sparkles", title: "Tinycast", subtitle: "Open anything", selected: true)
                row(symbol: "doc.on.clipboard", title: "Clipboard History", subtitle: "Recent copies")
            }
            .padding(Theme.Spacing.md)
            separator
            footer
        }
        .foregroundStyle(primary)
        .background(surface, in: shape)
        .overlay(shape.strokeBorder(primary.opacity(0.14), lineWidth: Theme.Size.hairline))
        .environment(\.colorScheme, appearance.colorScheme)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appearance.title) theme preview")
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            SymbolImage(name: "magnifyingglass", size: Theme.Size.quickActionHeaderIcon)
                .foregroundStyle(secondary)
            Text("Search for apps and commands…")
                .foregroundStyle(secondary)
            Spacer(minLength: Theme.Spacing.lg)
            Text("⌘ K")
                .font(Theme.Typography.keyCap)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(
                    primary.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: Theme.Radius.keyCap, style: .continuous))
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.headerHeight)
    }

    private func row(
        symbol: String, title: String, subtitle: String, selected: Bool = false
    ) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: symbol, size: Theme.Size.quickActionHeaderIcon)
                .foregroundStyle(selected ? accent : secondary)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(secondary)
            }
            Spacer(minLength: Theme.Spacing.lg)
            if selected {
                SymbolImage(name: "return", size: Theme.Size.quickActionHeaderIcon)
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            selected ? primary.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle()
                .fill(palette.support.success.swiftUIColor)
                .frame(width: Theme.Size.colorDot, height: Theme.Size.colorDot)
            Text("Ready")
                .foregroundStyle(secondary)
            Spacer(minLength: Theme.Spacing.lg)
            Text("Preview updates live")
                .font(.caption)
                .foregroundStyle(secondary)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.bottomBarHeight)
    }

    private var separator: some View {
        primary.opacity(0.10)
            .frame(height: Theme.Size.hairline)
    }

    private var surface: AnyShapeStyle {
        guard let gradient = palette.gradient else {
            return AnyShapeStyle(palette.panelBackground.swiftUIColor)
        }
        let radians = gradient.angle * .pi / 180
        let horizontal = CGFloat(cos(radians))
        let vertical = CGFloat(sin(radians))
        return AnyShapeStyle(
            LinearGradient(
                colors: [gradient.first.swiftUIColor, gradient.second.swiftUIColor],
                startPoint: UnitPoint(x: 0.5 - horizontal / 2, y: 0.5 - vertical / 2),
                endPoint: UnitPoint(x: 0.5 + horizontal / 2, y: 0.5 + vertical / 2)))
    }
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
