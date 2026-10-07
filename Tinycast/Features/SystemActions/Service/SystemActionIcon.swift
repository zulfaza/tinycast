import AppKit

extension SystemAction {
    /// A coloured tile, as System Settings groups its panes; the hue says what the action touches.
    var icon: EntryIcon {
        .tintedSymbol(name: sfSymbol, tint: tileTint.symbolTint)
    }

    private var tileTint: SystemActionTint {
        switch id {
        case .lockScreen, .toggleAppearance, .openTrash, .emptyTrash, .ejectAllDisks: return .gray
        case .sleep, .toggleStageManager: return .indigo
        case .sleepDisplays, .showDesktop, .toggleHiddenFiles, .hideOtherApps, .unhideAllApps,
            .toggleBluetooth:
            return .blue
        case .restart, .logOut: return .orange
        case .shutDown, .quitAllApps, .dismissNotifications: return .red
        case .showScreenSaver: return .teal
        case .playPause, .nextTrack, .previousTrack: return .pink
        case .toggleMute, .toggleMicrophoneMute, .volumeUp, .volumeDown, .setVolume, .volume0,
            .volume25, .volume50, .volume75, .volume100:
            return .rose
        }
    }
}

/// Fixed sRGB: the tile is rasterized off-main, where a dynamic colour resolves wrongly.
private enum SystemActionTint: String {
    case gray, indigo, blue, orange, red, teal, pink, rose

    var symbolTint: SymbolTint {
        let (red, green, blue): (CGFloat, CGFloat, CGFloat) =
            switch self {
            case .gray: (0.56, 0.56, 0.58)
            case .indigo: (0.37, 0.36, 0.90)
            case .blue: (0.04, 0.52, 1.00)
            case .orange: (1.00, 0.58, 0.04)
            case .red: (1.00, 0.27, 0.23)
            case .teal: (0.19, 0.69, 0.78)
            case .pink: (1.00, 0.22, 0.37)
            case .rose: (0.96, 0.30, 0.45)
            }
        return SymbolTint(
            key: "system-action-" + rawValue,
            color: NSColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    }
}
