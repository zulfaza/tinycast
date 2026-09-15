import Foundation

@main
nonisolated enum ClipboardTextHelper {
    static func main() async {
        guard CommandLine.arguments.count == 3,
            ["image", "pdf", "qr"].contains(CommandLine.arguments[1])
        else { exit(2) }
        do {
            let url = URL(fileURLWithPath: CommandLine.arguments[2])
            if CommandLine.arguments[1] == "qr" {
                let payloads = try await ClipboardTextExtractor.extractQRCodes(at: url)
                try FileHandle.standardOutput.write(contentsOf: try JSONEncoder().encode(payloads))
            } else {
                let text = try await ClipboardTextExtractor.extract(
                    at: url, isPDF: CommandLine.arguments[1] == "pdf")
                try FileHandle.standardOutput.write(contentsOf: Data(text.utf8))
            }
        } catch {
            exit(1)
        }
    }
}
