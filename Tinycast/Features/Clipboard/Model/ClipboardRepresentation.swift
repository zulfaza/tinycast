import Foundation

/// One pasteboard type, retaining one value for each source pasteboard item.
struct ClipboardRepresentation: Codable, Hashable, Sendable {
    let typeIdentifier: String
    let values: [Data]

    init(typeIdentifier: String, values: [Data]) {
        self.typeIdentifier = typeIdentifier
        self.values = values
    }

    var displayName: String {
        switch typeIdentifier {
        case "public.utf8-plain-text": return "Plain Text"
        case "public.rtf": return "Rich Text"
        case "public.html": return "HTML"
        case "public.url": return "URL"
        case "public.file-url": return "File"
        case "public.png": return "PNG"
        case "public.tiff": return "TIFF"
        default: return typeIdentifier.split(separator: ".").last.map(String.init) ?? typeIdentifier
        }
    }
}
