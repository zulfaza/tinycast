import Foundation

final class ExtensionTrace: @unchecked Sendable {
    static let defaultsKey = "TinycastExtensionTrace"

    private let lock = NSLock()
    private let fileURL: URL?
    private let enabled: Bool

    init() {
        enabled = ProcessInfo.processInfo.environment["TINYCAST_EXTENSION_TRACE"] == "1"
            || UserDefaults.standard.bool(forKey: Self.defaultsKey)
        guard enabled else {
            fileURL = nil
            return
        }
        let directory = AppPaths.applicationSupport().appendingPathComponent("Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("runtime.log")
        fileURL = target
        try? Data("\n--- Tinycast extension trace ---\n".utf8).write(to: target, options: .atomic)
    }

    func write(_ message: String) {
        guard enabled, let fileURL else { return }
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
