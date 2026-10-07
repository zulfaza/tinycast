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
                    .padding(.vertical, Theme.Spacing.md)
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
                Text("Accent marks the caret and focused controls.")
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

/// The palette at its real size, drawn from the draft, so every edit shows before it is anywhere else.
private struct ThemePreview: View {
    let palette: ThemePalette
    private let metrics = InterfaceMetrics.standard

    private var primary: Color { palette.primaryText.swiftUIColor }
    private var secondary: Color { palette.support.secondaryText.swiftUIColor }
    private var hairline: Color { primary.opacity(Theme.Size.themePreviewHairlineAlpha) }
    private var highlight: Color { primary.opacity(Theme.Size.themePreviewSelectionAlpha) }

    var body: some View {
        let scale = Theme.Size.themePreviewScale
        let width = metrics.size.panelWidth
        let height = Theme.Size.themePreviewPanelHeight + metrics.spacing.xxl + metrics.size.barButtonHeight
        scene
            .frame(width: width, height: height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width * scale, height: height * scale, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Theme preview")
    }

    private var scene: some View {
        VStack(spacing: metrics.spacing.xxl) {
            panel
                .overlay(alignment: .bottomTrailing) {
                    actionsMenu
                        .padding(.trailing, metrics.spacing.md)
                        .padding(.bottom, metrics.size.bottomBarHeight - metrics.spacing.xs)
                }
            hud
        }
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Favorites")
                row(path: "/System/Library/CoreServices/Finder.app", "Finder", selected: true)
                row(path: "/Applications/Safari.app", "Safari")
                sectionHeader("Applications")
                row(path: "/System/Applications/Calendar.app", "Calendar")
                row(path: "/System/Applications/Notes.app", "Notes")
                row(path: "/System/Applications/System Settings.app", "System Settings")
            }
            .padding(.horizontal, metrics.spacing.md)
            Spacer(minLength: 0)
            footer
        }
        .frame(width: metrics.size.panelWidth, height: Theme.Size.themePreviewPanelHeight)
        .background(background, in: shape)
        .overlay(shape.strokeBorder(hairline, lineWidth: Theme.Size.hairline))
        .clipShape(shape)
    }

    private var header: some View {
        HStack(spacing: metrics.spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(metrics.typography.headerIcon)
                .foregroundStyle(secondary)
                .frame(width: metrics.size.headerIconSlot)
            HStack(spacing: Theme.Size.hairline) {
                Rectangle()
                    .fill(palette.accent.swiftUIColor)
                    .frame(width: Theme.Size.hairline * 2, height: metrics.typography.searchFieldSize)
                Text("Search for apps and commands…")
                    .font(metrics.typography.searchField)
                    .foregroundStyle(secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: metrics.size.headerHeight)
        .padding(.horizontal, metrics.spacing.lg)
        .padding(.vertical, metrics.size.headerPadding)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(secondary)
            .padding(.horizontal, metrics.spacing.md)
            .padding(.top, metrics.spacing.sm)
            .padding(.bottom, metrics.spacing.sectionHeaderBottom)
    }

    private func row(path: String, _ title: String, selected: Bool = false) -> some View {
        HStack(spacing: metrics.spacing.lg) {
            Image(nsImage: IconCache.icon(forFile: path))
                .resizable()
                .interpolation(.high)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(title)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(primary)
            Spacer(minLength: metrics.spacing.lg)
            Text("Application")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(secondary)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            selected ? highlight : .clear,
            in: RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: metrics.spacing.md) {
            Image(systemName: "ellipsis")
                .font(metrics.typography.bar)
                .foregroundStyle(primary)
                .frame(width: metrics.size.barButtonHeight, height: metrics.size.barButtonHeight)
                .background(highlight, in: Circle())
            Spacer(minLength: 0)
            HStack(spacing: metrics.spacing.lg) {
                HStack(spacing: metrics.spacing.sm) {
                    Text("Open Application").foregroundStyle(primary)
                    keyCap("↵")
                }
                HStack(spacing: metrics.spacing.sm) {
                    Text("Actions").foregroundStyle(secondary)
                    keyCap("⌘")
                    keyCap("K")
                }
            }
            .font(metrics.typography.bar)
            .padding(.horizontal, metrics.spacing.lg)
            .frame(height: metrics.size.barButtonHeight + metrics.spacing.sm)
            .background(highlight, in: Capsule())
            .overlay(Capsule().strokeBorder(hairline, lineWidth: Theme.Size.hairline))
        }
        .padding(.horizontal, metrics.spacing.md)
        .frame(height: metrics.size.bottomBarHeight)
    }

    private func keyCap(_ glyph: String) -> some View {
        Text(glyph)
            .font(metrics.typography.keyCap)
            .foregroundStyle(secondary)
            .frame(minWidth: metrics.size.keyCap, minHeight: metrics.size.keyCap)
            .background(
                highlight, in: RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous))
    }

    private var actionsMenu: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.menuPanel, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            menuRow("arrow.up.forward.app", "Open Application", "↵", selected: true)
            menuRow("folder", "Show in Finder", "⌘↵")
            menuRow("doc.on.doc", "Copy Path", "⇧⌘C")
            Rectangle().fill(hairline).frame(height: Theme.Size.hairline)
                .padding(.vertical, metrics.spacing.xs)
            menuRow("trash", "Move to Trash", "⌃X", tint: palette.support.destructive.swiftUIColor)
        }
        .padding(metrics.spacing.sm)
        .frame(width: metrics.size.actionMenuWidth)
        .background(highlight, in: shape)
        .background(background, in: shape)
        // The panel colour is translucent by default; a menu over rows must not let them through.
        .background(palette.panelBackground.withAlpha(1).swiftUIColor, in: shape)
        .overlay(shape.strokeBorder(hairline, lineWidth: Theme.Size.hairline))
        .shadow(color: .black.opacity(Theme.Size.themePreviewShadowAlpha), radius: metrics.spacing.lg)
    }

    private func menuRow(
        _ symbol: String, _ title: String, _ shortcut: String, selected: Bool = false, tint: Color? = nil
    ) -> some View {
        HStack(spacing: metrics.spacing.md) {
            Image(systemName: symbol)
                .font(metrics.typography.menuIcon)
                .foregroundStyle(tint ?? secondary)
                .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
            Text(title)
                .font(metrics.typography.menuRow)
                .foregroundStyle(tint ?? primary)
            Spacer(minLength: metrics.spacing.md)
            Text(shortcut)
                .font(metrics.typography.menuShortcut)
                .foregroundStyle(secondary)
        }
        .padding(.horizontal, metrics.spacing.md)
        .frame(height: metrics.size.menuRowHeight)
        .background(
            selected ? highlight : .clear,
            in: RoundedRectangle(cornerRadius: metrics.radius.menuRow, style: .continuous))
    }

    private var hud: some View {
        HStack(spacing: metrics.spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(palette.support.success.swiftUIColor)
            Text("Copied to Clipboard").foregroundStyle(primary)
        }
        .font(metrics.typography.bar)
        .padding(.horizontal, metrics.spacing.xl)
        .frame(height: metrics.size.barButtonHeight)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(hairline, lineWidth: Theme.Size.hairline))
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
