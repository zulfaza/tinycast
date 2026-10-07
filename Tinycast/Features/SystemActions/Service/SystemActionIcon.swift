import AppKit

extension SystemAction {
    /// A coloured tile, as System Settings groups its panes; the hue says what the action touches.
    var icon: EntryIcon {
        .tintedSymbol(name: sfSymbol, tint: tileTint.symbolTint)
    }

    private var tileTint: TileTint {
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
