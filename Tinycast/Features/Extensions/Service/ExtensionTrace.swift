import Foundation

final class ExtensionTrace: @unchecked Sendable {
    static let defaultsKey = "extensionDeveloperMode"

    private let environmentEnabled = ProcessInfo.processInfo.environment["TINYCAST_EXTENSION_TRACE"] == "1"
    private let formatter = ISO8601DateFormatter()
    private let fileURL: URL
    private let lock = NSLock()
    private var openHandle: FileHandle?

    init() {
        fileURL = AppPaths.applicationSupport()
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("runtime.log")
    }

    deinit { try? openHandle?.close() }

    func write(_ message: String) {
        guard environmentEnabled || UserDefaults.standard.bool(forKey: Self.defaultsKey) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let handle = handle() else { return }
        try? handle.write(contentsOf: Data("\(formatter.string(from: Date())) \(message)\n".utf8))
    }

    /// Truncates on first write, so a log only ever holds the launch that is running.
    private func handle() -> FileHandle? {
        if let openHandle { return openHandle }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data("--- Tinycast extension trace ---\n".utf8).write(to: fileURL, options: .atomic)
        openHandle = try? FileHandle(forWritingTo: fileURL)
        _ = try? openHandle?.seekToEnd()
        return openHandle
    }
}
