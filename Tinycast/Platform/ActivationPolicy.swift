import AppKit

/// Keyed by window identity, not a count: a repeated open or close can't strand the Dock icon.
@MainActor
final class ActivationPolicy {
    private var openWindows: Set<ObjectIdentifier> = []

    var hasOpenWindows: Bool { !openWindows.isEmpty }
    /// LaunchServices answers its activation with a reopen event, which must not move the palette.
    private(set) var isReactivating = false

    func windowDidOpen(_ window: NSWindow) {
        openWindows.insert(ObjectIdentifier(window))
        NSApp.setActivationPolicy(.regular)
    }

    func windowDidClose(_ window: NSWindow) {
        openWindows.remove(ObjectIdentifier(window))
        if openWindows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    /// After the non-activating palette, cooperative activation can refuse us; LaunchServices won't.
    func activateIfRefused(raising window: NSWindow) {
        Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, let window, window.isVisible, !NSApp.isActive, !isReactivating
            else { return }
            isReactivating = true
            defer { isReactivating = false }
            _ = try? await NSWorkspace.shared.openApplication(
                at: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration())
            guard window.isVisible else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Each close reports back through `windowDidClose`, which drops the Dock icon after the last.
    func closeAll() {
        for window in NSApp.windows where openWindows.contains(ObjectIdentifier(window)) {
            window.close()
        }
    }
}
