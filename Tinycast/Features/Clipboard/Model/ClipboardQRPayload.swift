import Foundation

struct ClipboardQRPayload: Codable, Hashable, Sendable {
    static let maximumCount = 32
    static let maximumBytes = 8_192
    let value: String
    let isURL: Bool

    init(value: String) {
        self.init(value: value, isURL: URL(string: value)?.scheme?.isEmpty == false)
    }

    init(value: String, isURL: Bool) {
        self.value = value
        self.isURL = isURL
    }
}
