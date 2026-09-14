import Foundation
import Synchronization

/// Opt-in diagnostics for extension runtime failures and lifecycle timing.
final class ExtensionTrace: Sendable {
    static let defaultsKey = "extensionDeveloperMode"

    private let environmentEnabled =
        ProcessInfo.processInfo.environment["TINYCAST_EXTENSION_TRACE"] == "1"
    private let fileURL: URL
    private let state = Mutex(State())

    private struct State: Sendable {
        var openHandle: FileHandle?
        var bytesWritten = 0
    }

    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let maxLineBytes = 2 * 1024
    private static let maxFileBytes = 64 * 1024
    private static let header = Data("--- Tinycast extension trace ---\n".utf8)

    init() {
        fileURL = AppPaths.applicationSupport()
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("runtime.log")
    }

    deinit {
        state.withLock { state in
            try? state.openHandle?.close()
            state.openHandle = nil
        }
    }

    func write(_ message: String) {
        guard environmentEnabled || UserDefaults.standard.bool(forKey: Self.defaultsKey) else { return }
        let clean = message
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        let bounded = String(decoding: Data(clean.utf8).prefix(Self.maxLineBytes), as: UTF8.self)
        let line = Data("\(Date().formatted(Self.timestampStyle)) \(bounded)\n".utf8)
        state.withLock { state in
            guard state.bytesWritten + line.count <= Self.maxFileBytes else { return }
            if state.openHandle == nil {
                guard let handle = openHandle() else { return }
                state.openHandle = handle
                state.bytesWritten = Self.header.count
            }
            guard let handle = state.openHandle else { return }
            do {
                try handle.write(contentsOf: line)
                state.bytesWritten += line.count
            } catch {
                return
            }
        }
    }

    /// Truncate on first write so a log only holds the current launch.
    private func openHandle() -> FileHandle? {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? Self.header.write(to: fileURL, options: .atomic)) != nil else { return nil }
        let handle = try? FileHandle(forWritingTo: fileURL)
        _ = try? handle?.seekToEnd()
        return handle
    }
}
