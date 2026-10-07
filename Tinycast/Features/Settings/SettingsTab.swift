import SwiftUI

enum SettingsTab: CaseIterable, Identifiable {
    case general, customThemes, applications, systemSettings, systemActions, commands, quicklinks,
        appleShortcuts, fallbacks, clipboard, snippets, fileSearch, windowManagement, navigation, notes,
        calendar, emoji, dictation, ai, quickActions, extensions, permissions, backup, about
    /// The case, never an index: a selectable `List` flattens section and row IDs together.
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .customThemes: return "Custom Themes"
        case .applications: return "Applications"
        case .systemSettings: return "System Settings"
        case .systemActions: return "System Actions"
        case .commands: return "Commands"
        case .quicklinks: return "Quicklinks"
        case .appleShortcuts: return "Apple Shortcuts"
        case .fallbacks: return "Fallbacks"
        case .ai: return "AI"
        case .quickActions: return "Quick Actions"
        case .dictation: return "Dictation"
        case .fileSearch: return "File Search"
        case .notes: return "Notes"
        case .snippets: return "Snippets"
        case .navigation: return "Navigation"
        case .windowManagement: return "Window Management"
        case .clipboard: return "Clipboard"
        case .emoji: return "Emoji & Symbols"
        case .calendar: return "Calendar"
        case .extensions: return "Extensions"
        case .permissions: return "Permissions"
        case .backup: return "Backup"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .customThemes: return "paintpalette.fill"
        case .applications: return "square.grid.2x2.fill"
        case .systemSettings: return "gearshape.fill"
        case .systemActions: return "bolt.fill"
        case .commands: return "terminal.fill"
        case .quicklinks: return "link"
        case .appleShortcuts: return "square.2.layers.3d.fill"
        case .fallbacks: return "arrow.turn.down.right"
        case .ai: return "sparkles"
        case .quickActions: return "wand.and.sparkles"
        case .dictation: return "waveform"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .notes: return "text.page.fill"
        case .snippets: return "curlybraces"
        case .navigation: return "arrow.left.arrow.right"
        case .windowManagement: return "macwindow"
        case .clipboard: return "doc.on.clipboard.fill"
        case .emoji: return "face.smiling.inverse"
        case .calendar: return "calendar"
        case .extensions: return "puzzlepiece.extension.fill"
        case .permissions: return "hand.raised.fill"
        case .backup: return "clock.arrow.circlepath"
        case .about: return "info"
        }
    }

    /// The tile behind the glyph, as System Settings colours each pane.
    var tileColor: Color {
        switch self {
        case .general, .systemSettings, .fallbacks, .about: return .gray
        case .customThemes, .dictation: return .pink
        case .permissions, .quicklinks, .fileSearch: return .blue
        case .applications, .windowManagement: return .indigo
        case .systemActions, .emoji: return .yellow
        case .commands, .navigation: return .teal
        case .appleShortcuts, .ai: return .purple
        case .clipboard: return .brown
        case .snippets, .quickActions: return .cyan
        case .notes: return .orange
        case .calendar: return .red
        case .extensions: return .mint
        case .backup: return .green
        }
    }
}

/// Declaration order is display order; not `.Section`, which would shadow SwiftUI's `Section`.
enum SettingsSection: CaseIterable, Identifiable {
    case general, launcher, features, advanced
    /// See `SettingsTab.id`: distinct types keep the two namespaces from colliding.
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .launcher: return "Launcher"
        case .features: return "Features"
        case .advanced: return "Advanced"
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .general: return [.general, .customThemes, .permissions]
        case .launcher:
            return [
                .applications, .systemSettings, .systemActions, .commands, .quicklinks,
                .appleShortcuts, .fallbacks
            ]
        case .features:
            // Everyday tools first; AI and extensions are opt-in extras.
            return [
                .clipboard, .snippets, .fileSearch, .windowManagement, .navigation, .notes,
                .calendar, .emoji, .dictation, .ai, .quickActions, .extensions
            ]
        case .advanced: return [.backup, .about]
        }
    }
}
