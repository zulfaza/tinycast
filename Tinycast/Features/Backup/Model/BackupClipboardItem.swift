import Foundation

/// A clip in portable form: not `ClipboardItem`, whose `imagePath` names a file on one Mac.
struct BackupClipboardItem: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case text
        case image
        case file
    }

    var kind: Kind
    var text: String?
    /// A filename inside the bundle's `clipboard/images/`, never a path.
    var imageName: String?
    var createdAt: Date
    var sourceBundleID: String?
    var pinnedAt: Date?
    /// User label, retained independently from captured content.
    var name: String?
    /// Source pasteboard representations, in their original order.
    var representations: [ClipboardRepresentation]
    /// QR payload metadata extracted from image content.
    var qrPayloads: [ClipboardQRPayload]

    init(
        kind: Kind, text: String?, imageName: String?, createdAt: Date,
        sourceBundleID: String?, pinnedAt: Date?, name: String? = nil,
        representations: [ClipboardRepresentation] = [], qrPayloads: [ClipboardQRPayload] = []
    ) {
        self.kind = kind
        self.text = text
        self.imageName = imageName
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
        self.pinnedAt = pinnedAt
        self.name = name
        self.representations = representations
        self.qrPayloads = qrPayloads
    }
}
