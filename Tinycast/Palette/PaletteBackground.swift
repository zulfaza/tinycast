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
            // Square at full panel height: rounded glass feathers, and Liquid Glass thins when small.
            .background(alignment: .top) {
                Color.clear.glassEffect(.regular, in: Rectangle()).frame(height: glassHeight)
            }
            .onChange(of: window, initial: true) { applyShadow() }
            .onChange(of: usesSystemShadow) { applyShadow() }
    }

    private func applyShadow() {
        guard let window, window.hasShadow != usesSystemShadow else { return }
        window.hasShadow = usesSystemShadow
        window.invalidateShadow()
    }
}
