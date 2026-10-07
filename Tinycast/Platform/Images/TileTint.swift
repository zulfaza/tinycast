import AppKit

/// Fixed sRGB: a tile is rasterized off-main, where a dynamic colour resolves wrongly.
enum TileTint: String, Sendable {
    case gray, red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, rose, brown

    var color: NSColor {
        let (red, green, blue): (CGFloat, CGFloat, CGFloat) =
            switch self {
            case .gray: (0.56, 0.56, 0.58)
            case .red: (1.00, 0.27, 0.23)
            case .orange: (1.00, 0.58, 0.04)
            case .yellow: (1.00, 0.78, 0.00)
            case .green: (0.20, 0.78, 0.35)
            case .mint: (0.00, 0.78, 0.75)
            case .teal: (0.19, 0.69, 0.78)
            case .cyan: (0.35, 0.78, 0.98)
            case .blue: (0.04, 0.52, 1.00)
            case .indigo: (0.37, 0.36, 0.90)
            case .purple: (0.75, 0.35, 0.95)
            case .pink: (1.00, 0.22, 0.37)
            case .rose: (0.96, 0.30, 0.45)
            case .brown: (0.67, 0.52, 0.37)
            }
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
