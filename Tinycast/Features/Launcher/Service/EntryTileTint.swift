extension AppEntry {
    /// Symbol rows draw as their pane's tile, so a row and the sidebar agree on what owns it.
    var tileTint: TileTint? {
        switch kind {
        case .command, .quickAction:
            guard let command = CommandCatalog.command(for: self) else {
                return SettingsTab.quickActions.tileTint
            }
            return command.owner?.tileTint ?? command.unownedTint
        case .customCommand: return SettingsTab.commands.tileTint
        case .snippet: return SettingsTab.snippets.tileTint
        case .quicklink: return SettingsTab.quicklinks.tileTint
        case .systemAction: return SettingsTab.systemActions.tileTint
        case .windowCommand, .windowLayout, .windowRoom: return SettingsTab.windowManagement.tileTint
        case .meeting: return SettingsTab.calendar.tileTint
        case .application, .systemSettings, .appleShortcut, .extensionCommand: return nil
        }
    }
}

extension CommandID {
    fileprivate var unownedTint: TileTint {
        switch self {
        case .calculatorHistory: .orange
        case .define, .importFromRaycast, .quit: .red
        case .openCamera, .exportSettings, .importSettings: .green
        case .openInBrowser, .checkForUpdates: .blue
        case .support: .pink
        default: .gray
        }
    }
}
