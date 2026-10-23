import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
nonisolated enum ClipboardTextHelper {
    static func main() async {
        if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "thumbnail" {
            exit(writeThumbnail() ? 0 : 1)
        }
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

    /// `thumbnail <source> <copy> <edge>`: the full-size decode's memory leaves with this process.
    private static func writeThumbnail() -> Bool {
        let source = URL(fileURLWithPath: CommandLine.arguments[2])
        let copy = URL(fileURLWithPath: CommandLine.arguments[3])
        guard let edge = Int(CommandLine.arguments[4]),
            let image = CGImageSourceCreateWithURL(source as CFURL, nil),
            let decoded = CGImageSourceCreateThumbnailAtIndex(
                image, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: edge
                ] as CFDictionary)
        else { return false }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, decoded, nil)
        guard CGImageDestinationFinalize(destination) else { return false }
        var folder = copy.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        return (try? (data as Data).write(to: copy, options: .atomic)) != nil
    }
}
