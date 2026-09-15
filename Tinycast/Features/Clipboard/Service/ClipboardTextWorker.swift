import Foundation

/// Runs one `ClipboardTextHelper` per item, so Vision's allocations leave with the child process.
nonisolated enum ClipboardTextWorker {
    enum Failure: Error { case recognition, outputLimit }

    /// Mirrors `ClipboardTextExtractor.maximumTextBytes`: the helper is not in the app's module.
    private static let maximumOutputBytes = 32_000
    private static let maximumQROutputBytes = ClipboardQRPayload.maximumCount
        * (ClipboardQRPayload.maximumBytes * 6 + 64)
    private static let readSize = 4096
    /// The read loop and `waitUntilExit` block, so they stay off the cooperative pool.
    private static let queue = DispatchQueue(
        label: "com.tinycast.clipboard-text", qos: .background, attributes: .concurrent)

    static func extract(_ item: ClipboardItem) async throws -> String {
        guard let path = item.imagePath ?? item.filePath else { return "" }
        let kind = item.kind == .image ? ClipboardFileKind.image : ClipboardFileKind.of(path: path)
        guard kind == .image || kind == .pdf else { return "" }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ClipboardTextHelper")
        return try await extract(at: URL(fileURLWithPath: path), isPDF: kind == .pdf, executable: executable)
    }

    static func extractQR(_ item: ClipboardItem) async throws -> [ClipboardQRPayload] {
        guard let path = item.imagePath ?? item.filePath else { return [] }
        let kind = item.kind == .image ? ClipboardFileKind.image : ClipboardFileKind.of(path: path)
        guard kind == .image else { return [] }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ClipboardTextHelper")
        let data = try await extractRaw(
            arguments: ["qr", URL(fileURLWithPath: path).path], executable: executable,
            timeout: .seconds(60), maximumBytes: maximumQROutputBytes)
        return try JSONDecoder().decode([ClipboardQRPayload].self, from: data)
    }

    static func extract(
        at url: URL, isPDF: Bool, executable: URL, timeout: Duration = .seconds(60)
    ) async throws -> String {
        let data = try await extractRaw(
            arguments: [isPDF ? "pdf" : "image", url.path], executable: executable, timeout: timeout,
            maximumBytes: maximumOutputBytes)
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.recognition }
        return text
    }

    private static func extractRaw(
        arguments: [String], executable: URL, timeout: Duration, maximumBytes: Int
    ) async throws -> Data {
        try Task.checkCancellation()
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .background
        do { try process.run() } catch { throw Failure.recognition }
        // Cancellation can land between the check above and the launch, which nothing else catches.
        if Task.isCancelled { terminate(process) }
        let deadline = Task.detached(priority: .background) {
            do { try await Task.sleep(for: timeout) } catch { return }
            terminate(process)
        }
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(
                        returning: collect(from: process, reading: output, maximumBytes: maximumBytes))
                }
            }
        } onCancel: {
            terminate(process)
        }
        deadline.cancel()
        try Task.checkCancellation()
        return Data(try result.get().utf8)
    }

    /// Blocking throughout, and the only place a helper is reaped: every exit runs the `defer`.
    private static func collect(
        from process: Process, reading output: Pipe, maximumBytes: Int
    ) -> Result<String, Failure> {
        let reader = output.fileHandleForReading
        defer {
            terminate(process)
            process.waitUntilExit()
            try? reader.close()
        }
        var data = Data()
        do {
            while let chunk = try reader.read(upToCount: readSize), !chunk.isEmpty {
                data.append(chunk)
                if data.count > maximumBytes { return .failure(.outputLimit) }
            }
        } catch {
            return .failure(.recognition)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return .failure(.recognition)
        }
        return .success(text)
    }

    /// `terminate()` traps on a process that never launched, so the state has to be asked first.
    private static func terminate(_ process: Process) {
        if process.isRunning { process.terminate() }
    }
}
