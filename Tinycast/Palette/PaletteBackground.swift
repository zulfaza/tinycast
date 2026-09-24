import SwiftUI

struct PaletteBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let window: NSWindow?

    private var usesSystemShadow: Bool {
        colorScheme != .dark
    }

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.panelSurface())
            .background(GlassEffectView())
            .onChange(of: window, initial: true) { applyShadow() }
            .onChange(of: usesSystemShadow) { applyShadow() }
    }

    private func applyShadow() {
        guard let window, window.hasShadow != usesSystemShadow else { return }
        window.hasShadow = usesSystemShadow
        window.invalidateShadow()
    }
}
