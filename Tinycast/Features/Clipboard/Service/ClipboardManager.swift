import AppKit

@MainActor
final class ClipboardManager {
    /// Marker we attach to the pasteboard when *we* write to it, so polling ignores our own pastes.
    nonisolated static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")

    /// Longest text captured; bigger copies are skipped, truncation losing the tail.
    static let maxTextLength = 32_000

    /// Markers put on secret copies by password managers, browsers and the OS.
    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive")
    ]

    private let store: ClipboardStore
    private let settings: AppSettings
    private var timer: Timer?
    private var sessionTokens: [NotificationToken] = []
    private var lastChangeCount = 0
    private var isCapturing = false

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    // Isolated so teardown can touch the main-actor timer; the poll block is already weak.
    isolated deinit {
        timer?.invalidate()
    }

    func start() {
        guard !isCapturing else { return }
        isCapturing = true
        installSessionObservers()
        startPolling()
    }

    /// Turning the feature off: the poller, the observers and the drain all go with it.
    func stop() {
        isCapturing = false
        sessionTokens = []
        stopPolling()
    }

    // Fast user switching: another session's clipboard isn't ours, so stop waking up for it.
    private func installSessionObservers() {
        guard sessionTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stopPolling() }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.startPolling() }
                }, center: center)
        ]
    }

    // Re-baselining first is what stops a clip made in another session reading as new on resume.
    private func startPolling() {
        guard isCapturing, timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // Drain first: the real copy must reach history before we overwrite the pasteboard.
    func prepareForTinycastPasteboardMutation() {
        guard isCapturing else { return }
        poll()
    }

    // Load-bearing: a mismatched count means a foreign write the next poll must still see.
    func synchronizeAfterTinycastPasteboardMutation(changeCount: Int) {
        guard NSPasteboard.general.changeCount == changeCount else { return }
        lastChangeCount = changeCount
    }

    /// A Finder select-all must not insert ten thousand rows on one poll tick.
    nonisolated static let maxCapturedFiles = 32

    /// Reclaimable roots, without the `/private` that `resolvingSymlinksInPath` strips.
    nonisolated static let volatileRoots = [
        "/tmp/", "/var/tmp/", "/var/folders/", NSHomeDirectory() + "/Library/Caches/"
    ]

    /// Both parameters are injected environment facts, so a harness can drive its own scratch.
    nonisolated static func fileURLs(
        on pasteboard: NSPasteboard, volatileRoots roots: [String] = volatileRoots
    ) -> [String]? {
        let durable = PasteboardFiles.urls(on: pasteboard, limit: maxCapturedFiles) {
            isDurable($0, roots: roots)
        }
        // Nil rather than empty, so a copied `http` URL falls through and stays a link.
        guard !durable.isEmpty else { return nil }
        // Reversed on insert, so the first file copied ends up leading the history.
        return Array(durable.map(\.standardizedFileURL.path).reversed())
    }

    /// Copies every bounded source type, including formats Tinycast does not interpret itself.
    nonisolated static func representations(on pasteboard: NSPasteboard) -> [ClipboardRepresentation] {
        guard pasteboard.types?.isEmpty == false else { return [] }
        var order: [String] = []
        var values: [String: [Data]] = [:]
        var total = 0
        let items = pasteboard.pasteboardItems ?? []
        if items.isEmpty {
            for type in pasteboard.types ?? [] {
                let identifier = type.rawValue
                guard identifier != Self.internalType.rawValue, !identifier.isEmpty,
                    !order.contains(identifier),
                    order.count < ClipboardStore.maximumRepresentationCount
                else { continue }
                order.append(identifier)
            }
        } else {
            for item in items {
                for type in item.types {
                    let identifier = type.rawValue
                    guard identifier != Self.internalType.rawValue, !identifier.isEmpty,
                        !order.contains(identifier),
                        order.count < ClipboardStore.maximumRepresentationCount
                    else { continue }
                    order.append(identifier)
                }
                if order.count == ClipboardStore.maximumRepresentationCount { break }
            }
        }
        for identifier in order {
            let type = NSPasteboard.PasteboardType(identifier)
            var accepted: [Data] = []
            if items.isEmpty {
                if let data = pasteboard.data(forType: type) {
                    if data.count <= ClipboardStore.maximumRepresentationBytes,
                        total + data.count <= ClipboardStore.maximumRepresentationSetBytes
                    {
                        accepted.append(data)
                        total += data.count
                    }
                } else if let string = pasteboard.string(forType: type),
                    string.utf8.count <= ClipboardStore.maximumRepresentationBytes
                {
                    let data = Data(string.utf8)
                    if data.count <= ClipboardStore.maximumRepresentationBytes,
                        total + data.count <= ClipboardStore.maximumRepresentationSetBytes
                    {
                        accepted.append(data)
                        total += data.count
                    }
                }
            } else {
                for item in items {
                    guard accepted.count < ClipboardStore.maximumValuesPerRepresentation else { break }
                    let data: Data?
                    if let source = item.data(forType: type) {
                        data = source
                    } else if let string = item.string(forType: type),
                        string.utf8.count <= ClipboardStore.maximumRepresentationBytes
                    {
                        data = Data(string.utf8)
                    } else {
                        data = nil
                    }
                    guard let data, data.count <= ClipboardStore.maximumRepresentationBytes,
                        total + data.count <= ClipboardStore.maximumRepresentationSetBytes
                    else { continue }
                    accepted.append(data)
                    total += data.count
                }
            }
            if !accepted.isEmpty { values[identifier] = accepted }
            if total >= ClipboardStore.maximumRepresentationSetBytes { break }
        }
        return order.compactMap { identifier in
            values[identifier].map {
                ClipboardRepresentation(typeIdentifier: identifier, values: $0)
            }
        }
    }

    /// An app that stages a temp file beside better inline content must keep the inline content.
    nonisolated private static func isDurable(_ url: URL, roots: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var path = url.resolvingSymlinksInPath().path
        if path.hasPrefix("/private/") { path.removeFirst("/private".count) }
        return !roots.contains { path.hasPrefix($0) }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if pb.types?.contains(Self.internalType) == true { return }

        // Never record secrets: skip copies tagged sensitive by any of the marker owners.
        if let types = pb.types, !Set(types).isDisjoint(with: Self.sensitiveTypes) { return }

        // The pasteboard carries no source, so attribute it to the frontmost app.
        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleID, settings.clipboardDisabledApps.contains(sourceBundleID) { return }
        let representations = Self.representations(on: pb)

        // Ahead of the text branch: Finder puts the file's *name* on `.string` beside its URL.
        if let paths = Self.fileURLs(on: pb) {
            store.addFiles(paths, sourceBundleID: sourceBundleID, representations: representations)
            return
        }

        if let text = pb.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            guard text.count <= Self.maxTextLength else { return }
            store.addText(text, sourceBundleID: sourceBundleID, representations: representations)
            return
        }

        if let type = pb.availableType(from: [.png, .tiff]), let data = pb.data(forType: type) {
            let isPNG = type == .png
            let store = store
            // A big TIFF→PNG re-encode can take 100ms+, so keep the poll off that path.
            Task.detached(priority: .utility) {
                let png =
                    isPNG
                    ? data
                    : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
                guard let png else { return }
                await store.addImage(
                    png, sourceBundleID: sourceBundleID, representations: representations)
            }
        }
    }
}
