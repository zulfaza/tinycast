import Foundation
import Observation

/// AppCore-owned theme state; every mutation persists before views are re-rendered.
@MainActor
@Observable
final class CustomThemeStore {
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var theme: CustomTheme?
    private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.data(forKey: CustomThemeStorage.userDefaultsKey).flatMap { data in
            try? CustomThemeDocument.decode(data)
        }
    }

    var editableTheme: CustomTheme {
        theme ?? .defaults
    }

    func preview(_ theme: CustomTheme) throws {
        let data = try CustomThemeDocument(theme: theme).encoded()
        self.theme = theme
        defaults.set(data, forKey: CustomThemeStorage.userDefaultsKey)
        revision += 1
    }

    func reset() {
        theme = nil
        defaults.removeObject(forKey: CustomThemeStorage.userDefaultsKey)
        revision += 1
    }

    func importTheme(from data: Data) throws {
        try preview(CustomThemeDocument.decode(data))
    }

    func exportTheme() throws -> Data {
        try CustomThemeDocument(theme: editableTheme).encoded()
    }

}
