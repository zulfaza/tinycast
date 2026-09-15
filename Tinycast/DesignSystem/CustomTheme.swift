import Foundation

/// An sRGB colour that can safely cross the theme file boundary.
struct ThemeColor: Codable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init?(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        guard [red, green, blue, alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) })
        else { return nil }
        self.init(validRed: red, green: green, blue: blue, alpha: alpha)
    }

    fileprivate init(validRed red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let red = try values.decode(Double.self, forKey: .red)
        let green = try values.decode(Double.self, forKey: .green)
        let blue = try values.decode(Double.self, forKey: .blue)
        let alpha = try values.decode(Double.self, forKey: .alpha)
        guard let color = Self(red: red, green: green, blue: blue, alpha: alpha) else {
            throw DecodingError.dataCorruptedError(
                forKey: .red, in: values, debugDescription: "Theme colour components are invalid.")
        }
        self = color
    }

    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
        case alpha
    }

    func withAlpha(_ alpha: Double) -> ThemeColor {
        Self(validRed: red, green: green, blue: blue, alpha: max(0, min(1, alpha)))
    }
}

struct ThemeGradient: Codable, Hashable, Sendable {
    let first: ThemeColor
    let second: ThemeColor
    let angle: Double

    init?(first: ThemeColor, second: ThemeColor, angle: Double) {
        guard angle.isFinite else { return nil }
        self.first = first
        self.second = second
        self.angle = angle.truncatingRemainder(dividingBy: 360).normalizedAngle
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let first = try values.decode(ThemeColor.self, forKey: .first)
        let second = try values.decode(ThemeColor.self, forKey: .second)
        let angle = try values.decode(Double.self, forKey: .angle)
        guard let gradient = Self(first: first, second: second, angle: angle) else {
            throw DecodingError.dataCorruptedError(
                forKey: .angle, in: values, debugDescription: "Gradient angle is invalid.")
        }
        self = gradient
    }

    private enum CodingKeys: String, CodingKey {
        case first
        case second
        case angle
    }

    func adjustingAlpha(_ transform: (Double) -> Double) -> ThemeGradient {
        // The initializer's angle guard makes this construction safe.
        ThemeGradient(
            first: first.withAlpha(transform(first.alpha)),
            second: second.withAlpha(transform(second.alpha)),
            angle: angle
        ) ?? self
    }
}

struct ThemeSupportColors: Codable, Hashable, Sendable {
    var secondaryText: ThemeColor
    var success: ThemeColor
    var destructive: ThemeColor

    init(secondaryText: ThemeColor, success: ThemeColor, destructive: ThemeColor) {
        self.secondaryText = secondaryText
        self.success = success
        self.destructive = destructive
    }
}

struct ThemePalette: Codable, Hashable, Sendable {
    var panelBackground: ThemeColor
    var primaryText: ThemeColor
    var accent: ThemeColor
    var support: ThemeSupportColors
    var gradient: ThemeGradient?

    init(
        panelBackground: ThemeColor,
        primaryText: ThemeColor,
        accent: ThemeColor,
        support: ThemeSupportColors,
        gradient: ThemeGradient?
    ) {
        self.panelBackground = panelBackground
        self.primaryText = primaryText
        self.accent = accent
        self.support = support
        self.gradient = gradient
    }
}

struct CustomTheme: Codable, Hashable, Sendable {
    var name: String
    var light: ThemePalette
    var dark: ThemePalette

    init(name: String, light: ThemePalette, dark: ThemePalette) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled Theme" : name
        self.light = light
        self.dark = dark
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try values.decode(String.self, forKey: .name),
            light: try values.decode(ThemePalette.self, forKey: .light),
            dark: try values.decode(ThemePalette.self, forKey: .dark))
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case light
        case dark
    }

    static let defaults = CustomTheme(
        name: "Tinycast Defaults",
        light: ThemePalette(
            panelBackground: ThemeColor(validRed: 1, green: 1, blue: 1, alpha: 0.55),
            primaryText: ThemeColor(validRed: 0, green: 0, blue: 0, alpha: 1),
            accent: ThemeColor(validRed: 0.039, green: 0.518, blue: 1, alpha: 1),
            support: ThemeSupportColors(
                secondaryText: ThemeColor(validRed: 0, green: 0, blue: 0, alpha: 0.60),
                success: ThemeColor(validRed: 0, green: 1, blue: 0, alpha: 1),
                destructive: ThemeColor(validRed: 1, green: 0, blue: 0, alpha: 1)),
            gradient: nil),
        dark: ThemePalette(
            panelBackground: ThemeColor(validRed: 0, green: 0, blue: 0, alpha: 0.40),
            primaryText: ThemeColor(validRed: 1, green: 1, blue: 1, alpha: 1),
            accent: ThemeColor(validRed: 0.039, green: 0.518, blue: 1, alpha: 1),
            support: ThemeSupportColors(
                secondaryText: ThemeColor(validRed: 1, green: 1, blue: 1, alpha: 0.60),
                success: ThemeColor(validRed: 0, green: 1, blue: 0, alpha: 1),
                destructive: ThemeColor(validRed: 1, green: 0, blue: 0, alpha: 1)),
            gradient: nil))
}

struct CustomThemeDocument: Codable, Sendable {
    static let format = "tinycast-theme"
    static let currentVersion = 1

    let format: String
    let version: Int
    let theme: CustomTheme

    init(theme: CustomTheme) {
        format = Self.format
        version = Self.currentVersion
        self.theme = theme
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let format = try values.decode(String.self, forKey: .format)
        guard format == Self.format else { throw CustomThemeFileError.invalidFormat }
        let version = try values.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw CustomThemeFileError.unsupportedVersion(version)
        }
        self.format = format
        self.version = version
        theme = try values.decode(CustomTheme.self, forKey: .theme)
    }

    static func decode(_ data: Data) throws -> CustomTheme {
        let document = try JSONDecoder().decode(CustomThemeDocument.self, from: data)
        guard document.format == Self.format else { throw CustomThemeFileError.invalidFormat }
        guard document.version == Self.currentVersion else {
            throw CustomThemeFileError.unsupportedVersion(document.version)
        }
        return document.theme
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    private enum CodingKeys: String, CodingKey {
        case format
        case version
        case theme
    }
}

enum CustomThemeFileError: Error, Equatable {
    case invalidFormat
    case unsupportedVersion(Int)
}

enum CustomThemeStorage {
    static let userDefaultsKey = "customTheme"
}

private extension Double {
    var normalizedAngle: Double {
        self >= 0 ? self : self + 360
    }
}
