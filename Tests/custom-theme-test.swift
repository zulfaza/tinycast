import Foundation

@main
@MainActor
struct CustomThemeTests {
    static func main() {
        var failures = 0

        func check(_ condition: Bool, _ label: String) {
            if !condition {
                print("FAIL: \(label)")
                failures += 1
            }
        }

        let theme = CustomTheme.defaults
        let encoded = try? CustomThemeDocument(theme: theme).encoded()
        check(encoded != nil, "defaults encode")
        if let encoded, let decoded = try? CustomThemeDocument.decode(encoded) {
            check(decoded == theme, "defaults round-trip")
            check(decoded.light != decoded.dark, "light and dark remain separate")
            check(decoded.light.panelBackground.alpha == 0.55, "light reset panel alpha")
            check(decoded.dark.panelBackground.alpha == 0.40, "dark reset panel alpha")
            check(decoded.light.primaryText.red == 0, "light reset primary text")
            check(decoded.dark.primaryText.red == 1, "dark reset primary text")
            if let success = ThemeColor(red: 0, green: 1, blue: 0),
                let destructive = ThemeColor(red: 1, green: 0, blue: 0)
            {
                check(decoded.light.support.success == success, "default success colour")
                check(decoded.dark.support.success == success, "default dark success colour")
                check(
                    decoded.light.support.destructive == destructive,
                    "default destructive colour")
                check(
                    decoded.dark.support.destructive == destructive,
                    "default dark destructive colour")
            } else {
                check(false, "default support colours construct")
            }
        } else {
            check(false, "defaults decode")
        }

        check(
            ThemeColor(red: -0.1, green: 0, blue: 0) == nil,
            "negative components are rejected")
        check(
            ThemeColor(red: 0, green: 0, blue: 1.1) == nil,
            "components above one are rejected")
        check(
            ThemeColor(red: 0, green: 0, blue: 0, alpha: .infinity) == nil,
            "non-finite components are rejected")

        if let encoded {
            let malformed = String(decoding: encoded, as: UTF8.self)
                .replacingOccurrences(of: "tinycast-theme", with: "other")
            check(
                (try? CustomThemeDocument.decode(Data(malformed.utf8))) == nil,
                "unknown format is rejected")
        }
        do {
            _ = try CustomThemeDocument.decode(Data("{\"format\":\"other\",\"version\":1}".utf8))
            check(false, "unknown format reports a file error")
        } catch CustomThemeFileError.invalidFormat {
            check(true, "unknown format reports a file error")
        } catch {
            check(false, "unknown format reports a file error")
        }

        let gradient = ThemeGradient(
            first: theme.dark.panelBackground, second: theme.dark.primaryText, angle: -45)
        if let gradient {
            check(gradient.angle == 315, "gradient angles normalize")
            let adjusted = gradient.adjustingAlpha { $0 * 0.5 }
            check(adjusted.first.alpha == 0.2, "gradient alpha adjusts")
        } else {
            check(false, "gradient constructs")
        }

        let suiteName = "custom-theme-test-\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = CustomThemeStore(defaults: defaults)
            var edited = theme
            edited.name = "Edited"
            do {
                try store.preview(edited)
                check(store.theme == edited, "preview updates active theme")
                check(
                    defaults.data(forKey: CustomThemeStorage.userDefaultsKey) != nil,
                    "preview persists active theme")
                check(
                    CustomThemeStore(defaults: defaults).theme == edited,
                    "preview reloads persisted theme")
            } catch {
                check(false, "preview persists without error")
            }
            do {
                try store.importTheme(from: Data("{\"format\":\"other\"}".utf8))
                check(false, "invalid import rejected")
            } catch {
                check(store.theme == edited, "invalid import leaves active theme")
            }
            store.reset()
            check(store.theme == nil, "reset clears active theme")
            check(store.editableTheme == .defaults, "reset restores shipped defaults")
            check(
                defaults.data(forKey: CustomThemeStorage.userDefaultsKey) == nil,
                "reset clears persisted theme")
        } else {
            check(false, "test defaults suite creates")
        }

        print(
            failures == 0
                ? "custom-theme-test: all checks passed"
                : "custom-theme-test: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
