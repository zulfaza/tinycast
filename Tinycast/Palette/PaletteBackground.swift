import SwiftUI

struct PaletteBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let window: NSWindow?
    let glassHeight: CGFloat

    private var usesSystemShadow: Bool {
        colorScheme != .dark
    }

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.panelSurface())
            // Liquid Glass thins with its own size, so the compact bar keeps the full panel's glass.
            .background(alignment: .top) { GlassEffectView().frame(height: glassHeight) }
            .onChange(of: window, initial: true) { applyShadow() }
            .onChange(of: usesSystemShadow) { applyShadow() }
    }

    private func applyShadow() {
        guard let window, window.hasShadow != usesSystemShadow else { return }
        window.hasShadow = usesSystemShadow
        window.invalidateShadow()
    }
}
