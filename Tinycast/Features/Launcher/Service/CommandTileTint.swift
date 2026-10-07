extension AppEntry {
    /// Commands draw as their pane's tile, so a row and the sidebar agree on what owns it.
    var commandTint: TileTint? {
        switch kind {
        case .command, .quickAction:
            guard let command = CommandCatalog.command(for: self) else {
                return SettingsTab.quickActions.tileTint
            }
            return command.owner?.tileTint ?? command.unownedTint
        case .customCommand: return SettingsTab.commands.tileTint
        default: return nil
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
