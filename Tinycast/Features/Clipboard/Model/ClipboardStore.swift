import Foundation
import SQLite3

// Spelled as the C macro in sqlite3.h, which isn't imported into Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct ClipboardItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case text, image, file }

    let id: UUID
    let kind: Kind
    /// The copied text, or for a `.file` entry the absolute path — which is what FTS indexes.
    let text: String?
    /// Absolute path on disk; only files under `imagesDir` are ours to delete.
    let imagePath: String?
    let createdAt: Date
    /// Bundle ID of the app frontmost when the copy was captured (see `ClipboardManager.poll`).
    let sourceBundleID: String?
    /// When the entry was pinned; pins lead the list and are exempt from pruning.
    let pinnedAt: Date?
    /// User-provided label, searched alongside the captured content.
    let name: String?
    /// All paths copied in one pasteboard change, in source order.
    let filePaths: [String]

    var isPinned: Bool { pinnedAt != nil }

    /// The referenced path, so no call site re-derives a file entry's meaning from `text`.
    var filePath: String? { kind == .file ? filePaths.first : nil }

    init(text: String, sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: Date(),
            sourceBundleID: sourceBundleID, name: nil, filePaths: [])
    }

    init(imagePath: String, createdAt: Date = Date(), sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .image, text: nil, imagePath: imagePath, createdAt: createdAt,
            sourceBundleID: sourceBundleID, name: nil, filePaths: [])
    }

    /// Referenced where it lies: `imagePath` stays nil, keeping an unowned file from `deleteBlob`.
    init(filePath: String, createdAt: Date = Date(), sourceBundleID: String?) {
        self.init(
            id: UUID(), kind: .file, text: filePath, imagePath: nil, createdAt: createdAt,
            sourceBundleID: sourceBundleID, name: nil, filePaths: [filePath])
    }

    init(filePaths: [String], createdAt: Date = Date(), sourceBundleID: String?) {
        let ordered = Array(filePaths)
        self.init(
            id: UUID(), kind: .file, text: ordered.joined(separator: "\n"), imagePath: nil,
            createdAt: createdAt, sourceBundleID: sourceBundleID, name: nil, filePaths: ordered)
    }

    init(
        id: UUID, kind: Kind, text: String?, imagePath: String?, createdAt: Date,
        sourceBundleID: String?, pinnedAt: Date? = nil, name: String? = nil,
        filePaths: [String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
        self.pinnedAt = pinnedAt
        self.name = name
        let fallbackPaths: [String]
        if kind == .file, let text {
            fallbackPaths = text.split(separator: "\n").map(String.init)
        } else {
            fallbackPaths = []
        }
        self.filePaths = kind == .file && filePaths?.isEmpty != false
            ? fallbackPaths
            : filePaths ?? []
    }

    /// Copy with the two fields the store rewrites; the pin is always stated outright.
    func with(createdAt: Date? = nil, pinnedAt: Date?) -> ClipboardItem {
        ClipboardItem(
            id: id, kind: kind, text: text, imagePath: imagePath,
            createdAt: createdAt ?? self.createdAt, sourceBundleID: sourceBundleID,
            pinnedAt: pinnedAt, name: name, filePaths: filePaths)
    }

    func with(name: String?) -> ClipboardItem {
        ClipboardItem(
            id: id, kind: kind, text: text, imagePath: imagePath, createdAt: createdAt,
            sourceBundleID: sourceBundleID, pinnedAt: pinnedAt, name: name, filePaths: filePaths)
    }

    func with(filePaths: [String]) -> ClipboardItem {
        ClipboardItem(
            id: id, kind: kind, text: text, imagePath: imagePath, createdAt: createdAt,
            sourceBundleID: sourceBundleID, pinnedAt: pinnedAt, name: name, filePaths: filePaths)
    }

    /// Case-insensitive substring match: how the store filters without FTS.
    func matches(_ query: String) -> Bool {
        name?.localizedCaseInsensitiveContains(query) == true
            || text?.localizedCaseInsensitiveContains(query) == true
    }
}

/// Retention in days; `forever` is -1, so an unset key (0) falls through to the default.
enum ClipboardRetention: Int, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case sixMonths = 180
    case year = 365
    case forever = -1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .day: return "1 Day"
        case .week: return "1 Week"
        case .month: return "1 Month"
        case .threeMonths: return "3 Months"
        case .sixMonths: return "6 Months"
        case .year: return "1 Year"
        case .forever: return "Forever"
        }
    }

    var maxAge: TimeInterval {
        self == .forever ? .greatestFiniteMagnitude : TimeInterval(rawValue) * 86_400
    }
}

/// What ↵ does on a clipboard entry; ⌘↵ always does the other one.
enum ClipboardDefaultAction: String, CaseIterable, Identifiable, Sendable {
    case paste
    case copy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste: return "Paste"
        case .copy: return "Copy to Clipboard"
        }
    }
}

/// SQLite-backed clipboard history. See docs/features/clipboard.md#store.
@MainActor
@Observable
final class ClipboardStore {
    /// Newest-first with pins in place, every pin resident. docs/features/clipboard.md
    private(set) var items: [ClipboardItem] = [] {
        didSet {
            if !textSearchMatches.isEmpty {
                let current = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                textSearchMatches = textSearchMatches.map { current[$0.id] ?? $0 }
            }
            invalidateSearch(preservingMatches: true)
            onItemsChanged?()
        }
    }
    @ObservationIgnored var onItemsChanged: (() -> Void)?
    @ObservationIgnored var onSearchResultsChanged: ((String, [ClipboardItem], [ClipboardItem]) -> Void)?
    /// Rotated whenever the history is replaced, so a helper's late answer lands on nothing.
    @ObservationIgnored private(set) var extractionGeneration = UUID()
    /// The only thing a view observes for search freshness; `items` cannot speak for OCR.
    private var searchRevision = 0
    @ObservationIgnored private(set) var textSearchEnabled = false
    @ObservationIgnored private var textSearchActive = true
    @ObservationIgnored private var textSearchTask: Task<Void, Never>?
    @ObservationIgnored private var textSearchNeedsRefresh = false
    @ObservationIgnored private var textSearchQuery: String?
    @ObservationIgnored private var textSearchFilter: ClipboardFilter?
    @ObservationIgnored private var textSearchRequest: UUID?
    @ObservationIgnored private var textSearchMatches: [ClipboardItem] = []
    @ObservationIgnored private var representationsByID: [UUID: [ClipboardRepresentation]] = [:]
    @ObservationIgnored private var filePathsByID: [UUID: [String]] = [:]
    @ObservationIgnored private var namesByID: [UUID: String] = [:]
    @ObservationIgnored private var qrByID: [UUID: [ClipboardQRPayload]] = [:]
    @ObservationIgnored private var metadataLoadedIDs: Set<UUID> = []

    var maxAge: TimeInterval = ClipboardRetention.threeMonths.maxAge

    /// One-entry memo so repeated renders reuse the FTS result; cleared when `items` changes.
    @ObservationIgnored private var searchCache:
        (query: String, filter: ClipboardFilter, result: [ClipboardItem])?
    /// Same memo for the empty query, so the pinned split runs once per mutation.
    @ObservationIgnored private var orderedCache: [ClipboardItem]?

    nonisolated private static let memoryWindow = 1000
    /// The most unpinned rows any one query answers with, ordinary and OCR-only alike.
    nonisolated private static let searchLimit = 200
    nonisolated static let maximumRepresentationCount = 32
    nonisolated static let maximumValuesPerRepresentation = 32
    nonisolated static let maximumRepresentationBytes = 8 * 1024 * 1024
    nonisolated static let maximumRepresentationSetBytes = 32 * 1024 * 1024
    nonisolated private static let metadataCacheLimit = 1000
    nonisolated private static let maximumFilePathCount = 32
    nonisolated private static let maximumNameBytes = 1_024

    nonisolated private static let insertSQL = """
        INSERT INTO items(id, kind, text, image_path, created_at, source_app, pinned_at)
        VALUES(?,?,?,?,?,?,?)
        """

    private static let schema = """
        CREATE TABLE IF NOT EXISTS items(
          id TEXT NOT NULL UNIQUE,
          kind TEXT NOT NULL,
          text TEXT,
          image_path TEXT,
          created_at REAL NOT NULL,
          source_app TEXT,
          pinned_at REAL
        );
        CREATE INDEX IF NOT EXISTS items_created_at ON items(created_at);
        CREATE INDEX IF NOT EXISTS items_pinned_at ON items(pinned_at) WHERE pinned_at IS NOT NULL;
        CREATE TABLE IF NOT EXISTS item_names(
          item_id TEXT NOT NULL UNIQUE, name TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS item_files(
          item_id TEXT NOT NULL, ordinal INTEGER NOT NULL, path TEXT NOT NULL,
          PRIMARY KEY(item_id, ordinal)
        );
        CREATE TABLE IF NOT EXISTS item_representations(
          item_id TEXT NOT NULL, ordinal INTEGER NOT NULL, value_index INTEGER NOT NULL,
          type_identifier TEXT NOT NULL, data BLOB NOT NULL,
          PRIMARY KEY(item_id, ordinal, value_index)
        );
        CREATE TABLE IF NOT EXISTS item_qr(
          item_id TEXT NOT NULL, ordinal INTEGER NOT NULL, value TEXT NOT NULL, is_url INTEGER NOT NULL,
          PRIMARY KEY(item_id, ordinal)
        );
        CREATE TRIGGER IF NOT EXISTS items_metadata_ad AFTER DELETE ON items BEGIN
          DELETE FROM item_names WHERE item_id = old.id;
          DELETE FROM item_files WHERE item_id = old.id;
          DELETE FROM item_representations WHERE item_id = old.id;
          DELETE FROM item_qr WHERE item_id = old.id;
        END;
        CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
          text, content='items', content_rowid='rowid', tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
          INSERT INTO items_fts(rowid, text) VALUES(new.rowid, new.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
          INSERT INTO items_fts(items_fts, rowid, text) VALUES('delete', old.rowid, old.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE OF rowid, text ON items BEGIN
          INSERT INTO items_fts(items_fts, rowid, text) VALUES('delete', old.rowid, old.text);
          INSERT INTO items_fts(rowid, text) VALUES(new.rowid, new.text);
        END;
        """

    private static let extractionSchema = """
        CREATE TABLE IF NOT EXISTS item_text(
          item_id TEXT NOT NULL UNIQUE, text TEXT NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS item_text_fts USING fts5(
          text, content='item_text', content_rowid='rowid', tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS item_text_ai AFTER INSERT ON item_text BEGIN
          INSERT INTO item_text_fts(rowid, text) VALUES(new.rowid, new.text);
        END;
        CREATE TRIGGER IF NOT EXISTS item_text_ad AFTER DELETE ON item_text BEGIN
          INSERT INTO item_text_fts(item_text_fts, rowid, text)
            VALUES('delete', old.rowid, old.text);
        END;
        CREATE TRIGGER IF NOT EXISTS items_extract_ad AFTER DELETE ON items BEGIN
          DELETE FROM item_text WHERE item_id = old.id;
        END;
        CREATE TABLE IF NOT EXISTS item_text_failures(
          item_id TEXT NOT NULL UNIQUE, attempts INTEGER NOT NULL, retry_at REAL NOT NULL
        );
        CREATE TRIGGER IF NOT EXISTS items_extract_failure_ad AFTER DELETE ON items BEGIN
          DELETE FROM item_text_failures WHERE item_id = old.id;
        END;
        CREATE INDEX IF NOT EXISTS items_extract_candidates ON items(kind)
          WHERE kind IN ('image', 'file');
        """

    /// Internal, not private: a backup names both to stream the table and adopt its blobs.
    let imagesDir: URL
    let dbURL: URL
    @ObservationIgnored private var db: OpaquePointer?
    @ObservationIgnored private var insertStmt: OpaquePointer?
    @ObservationIgnored private var loadStmt: OpaquePointer?
    @ObservationIgnored private var windowFloorStmt: OpaquePointer?
    @ObservationIgnored private var searchStmt: OpaquePointer?
    @ObservationIgnored private var deleteByIDStmt: OpaquePointer?
    @ObservationIgnored private var pinStmt: OpaquePointer?
    @ObservationIgnored private var staleImagesStmt: OpaquePointer?
    @ObservationIgnored private var deleteStaleStmt: OpaquePointer?

    /// `directory` defaults to the per-channel store; the harness passes a throwaway one.
    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        dbURL = base.appendingPathComponent("clipboard.sqlite3")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        open()
    }

    /// Idempotent, so the coordinator can re-open the file when the feature is switched back on.
    func open() {
        guard db == nil else { return }
        if openDatabase() { return }
        // Captured, not authored: discard a corrupt or outdated database and start over.
        closeDatabase()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbURL.path + suffix)
        }
        if !openDatabase() { closeDatabase() }
    }

    /// Every accessor is statement-guarded, so a closed store answers as an empty history.
    func close() {
        setTextSearchEnabled(false)
        extractionGeneration = UUID()
        closeDatabase()
        representationsByID.removeAll()
        filePathsByID.removeAll()
        qrByID.removeAll()
        namesByID.removeAll()
        metadataLoadedIDs.removeAll()
        items = []
    }

    /// Application Support, not Caches: a history the OS may reclaim is not a history.
    private static var defaultDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    // Isolated so teardown may touch the main-actor pointers; the release is already on main.
    isolated deinit {
        textSearchTask?.cancel()
        closeDatabase()
    }

    func load() {
        invalidateSearch()
        extractionGeneration = UUID()
        loadMetadata()
        guard let stmt = loadStmt else { return }
        sqlite3_bind_int64(stmt, 1, windowFloor())
        var loaded: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = Self.row(stmt) { loaded.append(decorated(item)) }
        }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        items = loaded
        // Age passes while the app isn't running; insert-time pruning alone can't catch that.
        enforceLimits()
    }

    /// Called on load and when the retention setting changes.
    func enforceLimits() {
        prune()
    }

    /// The floor rowid `loadStmt` reads from; 0 means no floor, so load everything.
    private func windowFloor() -> sqlite3_int64 {
        guard let stmt = windowFloorStmt else { return 0 }
        defer {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        sqlite3_bind_int(stmt, 1, Int32(Self.memoryWindow - 1))
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }

    func addText(
        _ text: String, sourceBundleID: String?, representations: [ClipboardRepresentation] = []
    ) {
        if items.first?.kind == .text, items.first?.text == text { return }
        let item = ClipboardItem(text: text, sourceBundleID: sourceBundleID)
        insert(
            item,
            representations: representations.isEmpty ? Self.textRepresentation(text) : representations)
    }

    /// Paths arrive in insertion order; reverse them to retain the pasteboard's source order.
    func addFiles(
        _ paths: [String], sourceBundleID: String?, representations: [ClipboardRepresentation] = []
    ) {
        let ordered = Array(paths.reversed())
        guard !ordered.isEmpty else { return }
        if items.first?.kind == .file, items.first?.filePaths == ordered { return }
        let item = ClipboardItem(filePaths: ordered, sourceBundleID: sourceBundleID)
        insert(item, representations: representations, filePaths: ordered)
    }

    func addImage(
        _ data: Data, sourceBundleID: String?, representations: [ClipboardRepresentation] = []
    ) {
        let url = imagesDir.appendingPathComponent(UUID().uuidString + ".png")
        let item = ClipboardItem(imagePath: url.path, sourceBundleID: sourceBundleID)
        // The blob write is multi-MB I/O; only the row insert returns to the main actor.
        Task.detached(priority: .utility) { [weak self] in
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            await self?.insert(item, representations: representations)
        }
    }

    /// Inserts a captured item while retaining the source pasteboard types.
    func addCaptured(
        _ item: ClipboardItem, representations: [ClipboardRepresentation], filePaths: [String] = []
    ) {
        insert(item, representations: representations, filePaths: filePaths)
    }

    func representations(for item: ClipboardItem) -> [ClipboardRepresentation] {
        if let cached = representationsByID[item.id] { return cached }
        guard let db else { return [] }
        let statement = """
            SELECT ordinal, value_index, type_identifier, data
            FROM item_representations WHERE item_id = ?1
            ORDER BY ordinal, value_index
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, statement, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        let boundedResult = Self.readRepresentations(from: stmt)
        guard boundedResult.isEmpty else {
            cache(boundedResult, for: item.id, in: &representationsByID)
            return boundedResult
        }
        let fallback: [ClipboardRepresentation]
        switch item.kind {
        case .text:
            fallback = item.text.map(Self.textRepresentation) ?? []
        case .image:
            guard let path = item.imagePath, let data = try? Data(
                contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe),
                data.count <= Self.maximumRepresentationBytes
            else { return [] }
            fallback = [ClipboardRepresentation(typeIdentifier: "public.png", values: [data])]
        case .file:
            let urls = fileURLs(for: item)
            let fileData = urls.map(\.dataRepresentation)
            let pathData = urls.map { Data($0.path.utf8) }
            fallback = [
                ClipboardRepresentation(typeIdentifier: "public.file-url", values: fileData),
                ClipboardRepresentation(typeIdentifier: "public.utf8-plain-text", values: pathData)
            ]
        }
        cache(fallback, for: item.id, in: &representationsByID)
        return fallback
    }

    func rename(_ item: ClipboardItem, to name: String?) {
        let normalized = name.flatMap { (raw: String) -> String? in
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return String(decoding: cleaned.utf8.prefix(Self.maximumNameBytes), as: UTF8.self)
        }
        guard db != nil else { return }
        if let delete = prepare("DELETE FROM item_names WHERE item_id = ?1") {
            sqlite3_bind_text(delete, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(delete)
            sqlite3_finalize(delete)
        }
        if let normalized, let insert = prepare(
            "INSERT INTO item_names(item_id, name) VALUES(?1, ?2)"
        ) {
            sqlite3_bind_text(insert, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insert, 2, normalized, -1, SQLITE_TRANSIENT)
            sqlite3_step(insert)
            sqlite3_finalize(insert)
        }
        if let normalized {
            cache(normalized, for: item.id, in: &namesByID)
        } else {
            namesByID.removeValue(forKey: item.id)
        }
        markMetadataLoaded(item.id)
        updateItem(item.with(name: normalized))
    }

    @discardableResult
    func setQRCodes(
        _ payloads: [ClipboardQRPayload], for item: ClipboardItem, generation: UUID
    ) -> Bool {
        guard generation == extractionGeneration, db != nil else { return false }
        guard itemExists(item.id) else { return false }
        let bounded = Self.boundedQRCodes(payloads)
        guard let delete = prepare("DELETE FROM item_qr WHERE item_id = ?1"),
            let insert = prepare(
                "INSERT INTO item_qr(item_id, ordinal, value, is_url) VALUES(?1, ?2, ?3, ?4)"
            )
        else {
            return false
        }
        defer {
            sqlite3_finalize(delete)
            sqlite3_finalize(insert)
        }
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(delete, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(delete) == SQLITE_DONE else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        for (ordinal, payload) in bounded.enumerated() {
            sqlite3_bind_text(insert, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(insert, 2, Int32(ordinal))
            sqlite3_bind_text(insert, 3, payload.value, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(insert, 4, payload.isURL ? 1 : 0)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return false
            }
            sqlite3_reset(insert)
            sqlite3_clear_bindings(insert)
        }
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        cache(bounded, for: item.id, in: &qrByID)
        invalidateSearch(preservingMatches: true)
        searchRevision += 1
        return true
    }

    func qrPayloads(for item: ClipboardItem) -> [ClipboardQRPayload] {
        if let cached = qrByID[item.id] { return cached }
        guard let stmt = prepare(
            "SELECT value, is_url FROM item_qr WHERE item_id = ?1 ORDER BY ordinal"
        ) else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        let result = Self.readQRCodes(from: stmt)
        cache(result, for: item.id, in: &qrByID)
        return result
    }

    /// Bulk-insert from an import: original timestamps, external image paths, deduped.
    @discardableResult
    func importEntries(_ entries: [ClipboardItem]) -> Int {
        // Oldest first so newest ends up with the highest rowid (load orders by rowid DESC).
        let inserted = Self.importStoredItems(
            inDatabaseAt: dbURL, entries.sorted { $0.createdAt < $1.createdAt })
        load()
        return inserted
    }

    /// Move an item to the top; pasting or copying it from the palette re-recencies it.
    func promote(_ item: ClipboardItem) {
        // A pinned row holds its place, so re-recencying it would rewrite for no change.
        guard !item.isPinned, items.first?.id != item.id else { return }
        reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    func togglePinned(_ item: ClipboardItem) {
        if item.isPinned { unpin(item) } else { pin(item) }
    }

    func remove(_ item: ClipboardItem) {
        textSearchMatches.removeAll { $0.id == item.id }
        representationsByID.removeValue(forKey: item.id)
        filePathsByID.removeValue(forKey: item.id)
        namesByID.removeValue(forKey: item.id)
        qrByID.removeValue(forKey: item.id)
        metadataLoadedIDs.remove(item.id)
        if let stmt = deleteByIDStmt {
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        items.removeAll { $0.id == item.id }
        deleteBlob(item)
    }

    func clearAll() {
        invalidateSearch()
        extractionGeneration = UUID()
        if db != nil { sqlite3_exec(db, "DELETE FROM items", nil, nil, nil) }
        try? FileManager.default.removeItem(at: imagesDir)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        representationsByID.removeAll()
        filePathsByID.removeAll()
        namesByID.removeAll()
        qrByID.removeAll()
        metadataLoadedIDs.removeAll()
        items = []
    }

    @discardableResult
    func setTextSearchEnabled(_ enabled: Bool) -> Bool {
        guard enabled != textSearchEnabled else { return true }
        if enabled {
            guard let db, sqlite3_exec(db, Self.extractionSchema, nil, nil, nil) == SQLITE_OK else {
                return false
            }
            sqlite3_exec(db, "DELETE FROM item_text_failures", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM item_text WHERE text = ''", nil, nil, nil)
        }
        textSearchEnabled = enabled
        extractionGeneration = UUID()
        invalidateSearch()
        searchRevision += 1
        return true
    }

    func nextExtractionItem(now: Date = Date()) -> ClipboardItem? {
        guard textSearchEnabled else { return nil }
        guard
            let stmt = prepare(
                """
                SELECT id, kind, text, image_path, created_at, source_app, pinned_at
                FROM items WHERE kind IN ('image', 'file')
                  AND id NOT IN (SELECT item_id FROM item_text)
                  AND id NOT IN (SELECT item_id FROM item_text_failures
                    WHERE attempts >= 3 OR retry_at > ?1)
                ORDER BY rowid DESC LIMIT 1
                """)
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
        return sqlite3_step(stmt) == SQLITE_ROW ? Self.row(stmt) : nil
    }

    var nextExtractionRetry: Date? {
        guard textSearchEnabled,
            let stmt = prepare(
                "SELECT MIN(retry_at) FROM item_text_failures WHERE attempts < 3")
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
    }

    func recordExtractionFailure(for item: ClipboardItem, generation: UUID, retryAt: Date) {
        guard textSearchEnabled, generation == extractionGeneration,
            let stmt = prepare(
                """
                INSERT INTO item_text_failures(item_id, attempts, retry_at)
                SELECT id, 1, ?2 FROM items WHERE id = ?1
                ON CONFLICT(item_id) DO UPDATE SET attempts = attempts + 1, retry_at = excluded.retry_at
                """)
        else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, retryAt.timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    /// Selects the row rather than naming it, so an item deleted mid-recognition stays deleted.
    @discardableResult
    func setExtractedText(_ text: String, for item: ClipboardItem, generation: UUID) -> Bool {
        guard textSearchEnabled, generation == extractionGeneration,
            let stmt = prepare(
                """
                INSERT OR IGNORE INTO item_text(item_id, text)
                SELECT id, ?2 FROM items WHERE id = ?1 AND kind IN ('image', 'file')
                """)
        else { return false }
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, text, -1, SQLITE_TRANSIENT)
        let stored = sqlite3_step(stmt) == SQLITE_DONE && sqlite3_changes(db) > 0
        sqlite3_finalize(stmt)
        guard stored else { return false }
        if let stmt = prepare("DELETE FROM item_text_failures WHERE item_id = ?1") {
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        invalidateSearch(preservingMatches: true)
        searchRevision += 1
        return true
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        guard let path = item.imagePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    func fileURL(for item: ClipboardItem) -> URL? {
        guard let path = item.filePath else { return nil }
        return URL(fileURLWithPath: path)
    }

    func fileURLs(for item: ClipboardItem) -> [URL] {
        item.filePaths.prefix(Self.maximumFilePathCount).map(URL.init(fileURLWithPath:))
    }

    /// Display order for `query` under `filter`: pinned entries first, each block newest-first.
    func search(_ query: String, filter: ClipboardFilter) -> [ClipboardItem] {
        // Load-bearing: a settled OCR query changes the answer without `items` changing.
        _ = searchRevision
        let q = query.trimmingCharacters(in: .whitespaces)
        updateTextSearch(q, filter: filter)
        // The filter joins the key: `rows` rebuilds per render, so a query-only memo goes stale.
        if let searchCache, searchCache.query == q, searchCache.filter == filter {
            return searchCache.result
        }
        // Filtering after the split leaves a matching pin in the Pinned section, in pin order.
        let result = filter.apply(to: unfiltered(q, filter: filter))
        searchCache = (q, filter, result)
        return result
    }

    /// Row index of `item` as currently listed, so the palette can follow a row that moved.
    func rowIndex(of item: ClipboardItem, in query: String, filter: ClipboardFilter) -> Int? {
        search(query, filter: filter).firstIndex { $0.id == item.id }
    }

    /// The Nth visible pinned entry under `query` and `filter`, where 0 is the first pinned row.
    func pinnedItem(at index: Int, in query: String, filter: ClipboardFilter) -> ClipboardItem? {
        guard index >= 0 else { return nil }
        return search(query, filter: filter).prefix(while: \.isPinned).dropFirst(index).first
    }

    private func unfiltered(_ q: String, filter: ClipboardFilter) -> [ClipboardItem] {
        guard !q.isEmpty else { return orderedItems }
        // Pins are matched in memory: all resident, and the LIMIT would otherwise drop one.
        let ordinary = pinnedItems.filter { $0.matches(q) } + runSearch(q).filter { !$0.isPinned }
        guard !textSearchMatches.isEmpty else { return ordinary }
        let ordinaryIDs = Set(ordinary.map(\.id))
        let additional = textSearchMatches.filter { !ordinaryIDs.contains($0.id) }
        let pins = (ordinary + additional).filter(\.isPinned)
            .sorted { ($0.pinnedAt ?? .distantFuture) < ($1.pinnedAt ?? .distantFuture) }
        let unpinned = ordinary.filter { !$0.isPinned }
        // OCR-only rows fill what is left of the budget the FTS `LIMIT` gives ordinary ones.
        let remaining = max(0, Self.searchLimit - filter.apply(to: unpinned).count)
        // `Array(…)` spelled out: left open, `prefix` resolves as `Sequence` and the chain fails.
        let extra = Array(filter.apply(to: additional.filter { !$0.isPinned }).prefix(remaining))
        return pins + unpinned + extra
    }

    private func runSearch(_ q: String) -> [ClipboardItem] {
        // Trigram FTS needs ≥3 characters; shorter queries filter the in-memory window.
        guard let stmt = searchStmt, q.count >= 3 else { return fallbackSearch(q) }
        let match = "\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, Self.likePattern(q), -1, SQLITE_TRANSIENT)
        var results: [ClipboardItem] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            if let item = Self.row(stmt) { results.append(decorated(item)) }
            status = sqlite3_step(stmt)
        }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        return status == SQLITE_DONE ? results : fallbackSearch(q)
    }

    private func invalidateSearch(preservingMatches: Bool = false) {
        searchCache = nil
        orderedCache = nil
        textSearchTask?.cancel()
        textSearchTask = nil
        textSearchRequest = nil
        textSearchNeedsRefresh = preservingMatches && textSearchQuery != nil
        if !preservingMatches {
            textSearchQuery = nil
            textSearchFilter = nil
            textSearchMatches = []
        }
    }

    func setTextSearchActive(_ active: Bool) {
        guard textSearchActive != active else { return }
        textSearchActive = active
        guard textSearchEnabled else { return }
        invalidateSearch()
        searchRevision += 1
    }

    private func updateTextSearch(_ query: String, filter: ClipboardFilter) {
        guard textSearchEnabled, textSearchActive, !query.isEmpty,
            filter == .all || filter == .image || filter == .file
        else {
            if textSearchQuery != nil { invalidateSearch() }
            return
        }
        guard textSearchQuery != query || textSearchFilter != filter || textSearchNeedsRefresh else { return }
        invalidateSearch(preservingMatches: textSearchQuery == query && textSearchFilter == filter)
        textSearchNeedsRefresh = false
        textSearchQuery = query
        textSearchFilter = filter
        let request = UUID()
        textSearchRequest = request
        let url = dbURL
        let residentIDs = query.count < 3 ? Set(items.map(\.id)) : nil
        textSearchTask = Task(priority: .userInitiated) { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                Self.extractedMatches(in: url, query: query, filter: filter, residentIDs: residentIDs)
            }
            let matches = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self, self.textSearchRequest == request else { return }
            let previous = self.searchCache
            self.textSearchMatches = matches.map { self.decorated($0) }
            self.textSearchTask = nil
            self.searchCache = nil
            self.searchRevision += 1
            if let previous, previous.query == query {
                let current = self.search(query, filter: previous.filter)
                self.onSearchResultsChanged?(query, previous.result, current)
            }
        }
    }

    nonisolated private static func extractedMatches(
        in url: URL, query: String, filter: ClipboardFilter, residentIDs: Set<UUID>?
    ) -> [ClipboardItem] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return []
        }
        defer { sqlite3_close_v2(db) }
        sqlite3_exec(db, "PRAGMA cache_size=-2048", nil, nil, nil)
        sqlite3_progress_handler(db, 1000, { _ in Task.isCancelled ? 1 : 0 }, nil)
        let isShort = query.count < 3
        let kind = filter == .image ? "i.kind = 'image'" : filter == .file ? "i.kind = 'file'" : "1"
        let columns = "i.id, i.kind, i.text, i.image_path, i.created_at, i.source_app, i.pinned_at"
        let sql =
            isShort
            ? """
            SELECT \(columns), t.text FROM item_text t JOIN items i ON i.id = t.item_id
            WHERE \(kind) AND (i.pinned_at IS NOT NULL OR i.rowid >= COALESCE(
              (SELECT rowid FROM items WHERE pinned_at IS NULL ORDER BY rowid DESC LIMIT 1 OFFSET \(memoryWindow - 1)), 0))
            ORDER BY i.pinned_at IS NULL, i.pinned_at, i.rowid DESC
            """
            : """
            SELECT * FROM (
              SELECT \(columns), NULL AS recognized, i.rowid AS rid FROM items i
                WHERE i.pinned_at IS NULL AND i.rowid IN (
                SELECT i.rowid FROM item_text_fts f
                  JOIN item_text t ON t.rowid = f.rowid JOIN items i ON i.id = t.item_id
                WHERE item_text_fts MATCH ?1 AND \(kind)
                ORDER BY i.rowid DESC
                LIMIT \(searchLimit) + (SELECT COUNT(*) FROM items WHERE pinned_at IS NOT NULL)
              )
              UNION ALL
              SELECT \(columns), t.text AS recognized, i.rowid AS rid
                FROM items i JOIN item_text t ON t.item_id = i.id
                WHERE i.pinned_at IS NOT NULL AND \(kind)
            ) ORDER BY pinned_at IS NULL, pinned_at, rid DESC
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        if !isShort {
            let match = "\"" + query.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
        }
        var matches: [ClipboardItem] = []
        var unpinned = 0
        while !Task.isCancelled, sqlite3_step(stmt) == SQLITE_ROW {
            guard let item = row(stmt) else { continue }
            if let residentIDs, !residentIDs.contains(item.id) { continue }
            if isShort || item.isPinned,
                columnString(stmt, 7)?.localizedCaseInsensitiveContains(query) != true
            {
                continue
            }
            matches.append(item)
            if !item.isPinned { unpinned += 1 }
            if unpinned == searchLimit { break }
        }
        return Task.isCancelled ? [] : matches
    }

    // MARK: - Private

    private func fallbackSearch(_ q: String) -> [ClipboardItem] {
        items.filter { item in
            item.matches(q)
                || qrPayloads(for: item).contains {
                    $0.value.localizedCaseInsensitiveContains(q)
                }
        }
    }

    private var orderedItems: [ClipboardItem] {
        if let orderedCache { return orderedCache }
        let pinned = pinnedItems
        // An unpinned history renders `items` as-is, so it never pays for the split.
        let result = pinned.isEmpty ? items : pinned + items.filter { !$0.isPinned }
        orderedCache = result
        return result
    }

    /// The Pinned section in pin order, so a new pin joins the end rather than the head.
    private var pinnedItems: [ClipboardItem] {
        items.filter(\.isPinned)
            .sorted { ($0.pinnedAt ?? .distantFuture) < ($1.pinnedAt ?? .distantFuture) }
    }

    private func itemExists(_ id: UUID) -> Bool {
        guard let stmt = prepare("SELECT 1 FROM items WHERE id = ?1") else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func cache<Value>(_ value: Value, for id: UUID, in cache: inout [UUID: Value]) {
        if cache.count >= Self.metadataCacheLimit, let evicted = cache.keys.first, evicted != id {
            cache.removeValue(forKey: evicted)
        }
        cache[id] = value
    }

    /// The row keeps its place and gains a stamp, which heads the Pinned section.
    private func pin(_ item: ClipboardItem) {
        let stamp = Date()
        let current = items.first { $0.id == item.id } ?? item
        let pinned = current.with(pinnedAt: stamp)
        if let stmt = pinStmt {
            sqlite3_bind_double(stmt, 1, stamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = pinned
        } else {
            // Pinned from an FTS hit outside the window, so splice it in by recency.
            let index = items.firstIndex { $0.createdAt < pinned.createdAt } ?? items.count
            items.insert(pinned, at: index)
        }
    }

    /// Unpinning rejoins as the newest entry. See docs/features/clipboard.md#pinned-entries.
    private func unpin(_ item: ClipboardItem) {
        reinsert(item.with(createdAt: Date(), pinnedAt: nil))
    }

    /// Rewrites the row under the same id so it leads; a delete would take its derived text too.
    private func reinsert(_ updated: ClipboardItem) {
        if let stmt = prepare(
            """
            UPDATE items SET rowid = (SELECT COALESCE(MAX(rowid), 0) + 1 FROM items),
              created_at = ?1, pinned_at = ?2 WHERE id = ?3
            """)
        {
            sqlite3_bind_double(stmt, 1, updated.createdAt.timeIntervalSince1970)
            if let stamp = updated.pinnedAt {
                sqlite3_bind_double(stmt, 2, stamp.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_text(stmt, 3, updated.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        // Array ops also cover items surfaced by FTS from beyond the in-memory window.
        items.removeAll { $0.id == updated.id }
        items.insert(updated, at: 0)
        trimWindow()
    }

    /// Cap the in-memory window, but never drop a pinned row: those render however old they are.
    private func trimWindow() {
        guard items.count > Self.memoryWindow, let index = items.lastIndex(where: { !$0.isPinned })
        else { return }
        items.remove(at: index)
    }

    private func insert(
        _ item: ClipboardItem, representations: [ClipboardRepresentation] = [],
        filePaths: [String] = []
    ) {
        let paths = filePaths.isEmpty ? item.filePaths : filePaths
        let safeRepresentations = Self.boundedRepresentations(representations)
        if let stmt = insertStmt { Self.bindAndInsert(stmt, item) }
        writeMetadata(for: item, representations: safeRepresentations, filePaths: paths)
        cache(safeRepresentations, for: item.id, in: &representationsByID)
        cache(Array(paths.prefix(Self.maximumFilePathCount)), for: item.id, in: &filePathsByID)
        if let name = item.name { cache(name, for: item.id, in: &namesByID) }
        items.insert(decorated(item), at: 0)
        trimWindow()
        prune()
    }

    private func updateItem(_ updated: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == updated.id }) {
            items[index] = updated
        }
        searchCache = nil
        orderedCache = nil
    }

    private func writeMetadata(
        for item: ClipboardItem, representations: [ClipboardRepresentation], filePaths: [String]
    ) {
        let boundedPaths = Array(filePaths.prefix(Self.maximumFilePathCount))
        if let name = item.name, let stmt = prepare(
            "INSERT OR REPLACE INTO item_names(item_id, name) VALUES(?1, ?2)"
        ) {
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        if !boundedPaths.isEmpty, let stmt = prepare(
            "INSERT INTO item_files(item_id, ordinal, path) VALUES(?1, ?2, ?3)"
        ) {
            for (ordinal, path) in boundedPaths.enumerated() {
                sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(ordinal))
                sqlite3_bind_text(stmt, 3, path, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
            }
            sqlite3_finalize(stmt)
        }
        guard !representations.isEmpty, let stmt = prepare(
            """
            INSERT INTO item_representations(item_id, ordinal, value_index, type_identifier, data)
            VALUES(?1, ?2, ?3, ?4, ?5)
            """
        ) else { return }
        for (ordinal, representation) in representations.enumerated() {
            for (index, data) in representation.values.enumerated() {
                sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(ordinal))
                sqlite3_bind_int(stmt, 3, Int32(index))
                sqlite3_bind_text(stmt, 4, representation.typeIdentifier, -1, SQLITE_TRANSIENT)
                data.withUnsafeBytes { bytes in
                    _ = sqlite3_bind_blob(
                        stmt, 5, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
            }
        }
        sqlite3_finalize(stmt)
    }

    private func loadMetadata() {
        // Representations can be large; rows load their metadata only when they become visible.
        representationsByID.removeAll()
        filePathsByID.removeAll()
        namesByID.removeAll()
        qrByID.removeAll()
        metadataLoadedIDs.removeAll()
    }

    private func decorated(_ item: ClipboardItem) -> ClipboardItem {
        loadMetadata(for: item.id)
        let paths = filePathsByID[item.id] ?? item.filePaths
        let name = item.name ?? namesByID[item.id]
        return item.with(filePaths: paths).with(name: name)
    }

    private func loadMetadata(for id: UUID) {
        guard !metadataLoadedIDs.contains(id), db != nil else { return }
        markMetadataLoaded(id)
        if let stmt = prepare("SELECT name FROM item_names WHERE item_id = ?1") {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW, let name = Self.columnString(stmt, 0) {
                cache(name, for: id, in: &namesByID)
            }
        }
        if let stmt = prepare(
            "SELECT path FROM item_files WHERE item_id = ?1 ORDER BY ordinal"
        ) {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            var paths: [String] = []
            while paths.count < Self.maximumFilePathCount, sqlite3_step(stmt) == SQLITE_ROW {
                if let path = Self.columnString(stmt, 0) { paths.append(path) }
            }
            if !paths.isEmpty { cache(paths, for: id, in: &filePathsByID) }
        }
    }

    private func markMetadataLoaded(_ id: UUID) {
        if metadataLoadedIDs.count >= Self.metadataCacheLimit,
            let evicted = metadataLoadedIDs.first, evicted != id
        {
            metadataLoadedIDs.remove(evicted)
            namesByID.removeValue(forKey: evicted)
            filePathsByID.removeValue(forKey: evicted)
        }
        metadataLoadedIDs.insert(id)
    }

    nonisolated private static func textRepresentation(_ text: String) -> [ClipboardRepresentation] {
        [ClipboardRepresentation(typeIdentifier: "public.utf8-plain-text", values: [Data(text.utf8)])]
    }

    nonisolated private static func likePattern(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "//")
            .replacingOccurrences(of: "%", with: "/%")
            .replacingOccurrences(of: "_", with: "/_")
    }

    nonisolated private static func boundedRepresentations(
        _ representations: [ClipboardRepresentation]
    ) -> [ClipboardRepresentation] {
        var total = 0
        var result: [ClipboardRepresentation] = []
        for representation in representations.prefix(maximumRepresentationCount) {
            guard !representation.typeIdentifier.isEmpty else { continue }
            var values: [Data] = []
            for data in representation.values.prefix(maximumValuesPerRepresentation) {
                guard data.count <= maximumRepresentationBytes,
                    total + data.count <= maximumRepresentationSetBytes
                else { continue }
                values.append(data)
                total += data.count
            }
            if !values.isEmpty {
                result.append(
                    ClipboardRepresentation(typeIdentifier: representation.typeIdentifier, values: values))
            }
            guard total < maximumRepresentationSetBytes else { break }
        }
        return result
    }

    nonisolated private static func boundedName(_ name: String) -> String {
        String(decoding: name.trimmingCharacters(in: .whitespacesAndNewlines)
            .utf8.prefix(maximumNameBytes), as: UTF8.self)
    }

    nonisolated private static func boundedQRCodes(
        _ payloads: [ClipboardQRPayload]
    ) -> [ClipboardQRPayload] {
        payloads.reduce(into: [ClipboardQRPayload]()) { result, payload in
            guard result.count < ClipboardQRPayload.maximumCount,
                !payload.value.isEmpty,
                payload.value.utf8.count <= ClipboardQRPayload.maximumBytes,
                !result.contains(payload)
            else { return }
            result.append(payload)
        }
    }

    nonisolated private static func bindAndInsert(_ stmt: OpaquePointer, _ item: ClipboardItem) {
        sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, item.kind.rawValue, -1, SQLITE_TRANSIENT)
        if let text = item.text {
            sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        if let path = item.imagePath {
            sqlite3_bind_text(stmt, 4, path, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_double(stmt, 5, item.createdAt.timeIntervalSince1970)
        if let source = item.sourceBundleID {
            sqlite3_bind_text(stmt, 6, source, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        if let pinnedAt = item.pinnedAt {
            sqlite3_bind_double(stmt, 7, pinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        sqlite3_step(stmt)
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
    }

    /// Whether a path is inside our images directory; only those are ours to delete.
    private func owns(_ path: String) -> Bool {
        path.hasPrefix(imagesDir.path + "/")
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        textSearchMatches.removeAll { $0.createdAt < cutoff && !$0.isPinned }
        if let imagesStmt = staleImagesStmt, let deleteStmt = deleteStaleStmt {
            sqlite3_bind_double(imagesStmt, 1, cutoff.timeIntervalSince1970)
            var staleOwnedPaths: [String] = []
            while sqlite3_step(imagesStmt) == SQLITE_ROW {
                // Only delete files we own; an external reference just loses its row.
                if let path = Self.columnString(imagesStmt, 0), owns(path) {
                    staleOwnedPaths.append(path)
                }
            }
            sqlite3_reset(imagesStmt)
            sqlite3_clear_bindings(imagesStmt)
            sqlite3_bind_double(deleteStmt, 1, cutoff.timeIntervalSince1970)
            sqlite3_step(deleteStmt)
            if sqlite3_changes(db) > 0 {
                invalidateSearch(preservingMatches: true)
                searchRevision += 1
            }
            sqlite3_reset(deleteStmt)
            sqlite3_clear_bindings(deleteStmt)
            // A retention cut can strand hundreds of files, so delete them off the main actor.
            if !staleOwnedPaths.isEmpty {
                Task.detached(priority: .utility) {
                    for path in staleOwnedPaths {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                }
            }
        }
        // Against the oldest unpinned row: an exempt pin would make this permanently true.
        if items.last(where: { !$0.isPinned }).map({ $0.createdAt < cutoff }) == true {
            items.removeAll { $0.createdAt < cutoff && !$0.isPinned }
        }
    }

    private func deleteBlob(_ item: ClipboardItem) {
        guard let path = item.imagePath, owns(path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func openDatabase() -> Bool {
        guard
            sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
                == SQLITE_OK,
            sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
                == SQLITE_OK,
            sqlite3_exec(db, Self.schema, nil, nil, nil) == SQLITE_OK
        else { return false }
        insertStmt = prepare(Self.insertSQL)
        // Two indexed branches, deliberately not one OR. See docs/features/clipboard.md#store.
        loadStmt = prepare(
            """
            SELECT id, kind, text, image_path, created_at, source_app, pinned_at FROM (
              SELECT rowid AS rid, * FROM items WHERE rowid >= ?1
              UNION ALL
              SELECT rowid AS rid, * FROM items WHERE pinned_at IS NOT NULL AND rowid < ?1
            ) ORDER BY rid DESC
            """)
        windowFloorStmt = prepare(
            "SELECT rowid FROM items WHERE pinned_at IS NULL ORDER BY rowid DESC LIMIT 1 OFFSET ?")
        searchStmt = prepare(
            """
            SELECT i.id, i.kind, i.text, i.image_path, i.created_at, i.source_app, i.pinned_at
            FROM items i
            WHERE i.rowid IN (
              SELECT rowid FROM items_fts WHERE items_fts MATCH ?1
              ORDER BY rowid DESC LIMIT \(Self.searchLimit)
            ) OR i.id IN (
              SELECT item_id FROM item_names
              WHERE name COLLATE NOCASE LIKE '%' || ?2 || '%' ESCAPE '/'
            ) OR i.id IN (
              SELECT item_id FROM item_qr
              WHERE value COLLATE NOCASE LIKE '%' || ?2 || '%' ESCAPE '/'
            )
            ORDER BY i.rowid DESC LIMIT \(Self.searchLimit)
            """)
        deleteByIDStmt = prepare("DELETE FROM items WHERE id = ?")
        // Only ever sets a stamp: unpinning rewrites the whole row so it leads the history again.
        pinStmt = prepare("UPDATE items SET pinned_at = ? WHERE id = ?")
        staleImagesStmt = prepare(
            """
            SELECT image_path FROM items
            WHERE created_at < ? AND pinned_at IS NULL AND image_path IS NOT NULL
            """)
        deleteStaleStmt = prepare("DELETE FROM items WHERE created_at < ? AND pinned_at IS NULL")
        return insertStmt != nil && loadStmt != nil && windowFloorStmt != nil && searchStmt != nil
            && deleteByIDStmt != nil && pinStmt != nil && staleImagesStmt != nil
            && deleteStaleStmt != nil
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private func closeDatabase() {
        [
            insertStmt, loadStmt, windowFloorStmt, searchStmt, deleteByIDStmt, pinStmt,
            staleImagesStmt, deleteStaleStmt
        ].forEach { sqlite3_finalize($0) }
        insertStmt = nil
        loadStmt = nil
        windowFloorStmt = nil
        searchStmt = nil
        deleteByIDStmt = nil
        pinStmt = nil
        staleImagesStmt = nil
        deleteStaleStmt = nil
        sqlite3_close_v2(db)
        db = nil
    }

    /// Staged blobs move into `imagesDirectory` so retention can reclaim them after import.
    nonisolated static func importStoredItems(
        inDatabaseAt url: URL, adoptingImagesInto imagesDirectory: URL? = nil,
        _ items: some Sequence<ClipboardItem>, metadata: [UUID: StoredMetadata] = [:]
    ) -> Int {
        let entries = items.lazy.map { item in
            StoredEntry(
                item: item,
                metadata: metadata[item.id] ?? StoredMetadata(
                    name: item.name, filePaths: item.filePaths, representations: [], qrPayloads: []))
        }
        return importStoredEntries(
            inDatabaseAt: url, adoptingImagesInto: imagesDirectory, entries)
    }

    /// Streams items and their metadata through one transaction without staging the history.
    nonisolated static func importStoredEntries(
        inDatabaseAt url: URL, adoptingImagesInto imagesDirectory: URL? = nil,
        _ entries: some Sequence<StoredEntry>
    ) -> Int {
        var keys: Set<Int> = []
        forEachStoredItem(inDatabaseAt: url) { keys.insert(importKey($0)) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return 0
        }
        defer { sqlite3_close_v2(db) }
        // A capture from the poller can hold the write lock; without this the import truncates.
        sqlite3_busy_timeout(db, 5_000)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        var inserted = 0
        // One transaction for the batch: ~1 WAL commit rather than one per row.
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        for entry in entries {
            let item = adoptionTarget(entry.item, in: imagesDirectory)
            guard keys.insert(importKey(item)).inserted else { continue }
            if item.imagePath != entry.item.imagePath,
                !moveBlob(from: entry.item.imagePath, to: item.imagePath)
            {
                continue
            }
            bindAndInsert(stmt, item)
            writeMetadata(entry.metadata, for: item, in: db)
            inserted += 1
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        return inserted
    }

    /// Hashed, never held: a whole history's text must not sit in memory to dedupe an import.
    nonisolated private static func importKey(_ item: ClipboardItem) -> Int {
        var hasher = Hasher()
        hasher.combine(item.kind)
        // Keyed off `text` for everything but an image, or every file entry hashes alike.
        hasher.combine(item.kind == .image ? item.imagePath : item.text)
        return hasher.finalize()
    }

    /// Preserve the bundle name so repeat imports dedupe instead of minting another image.
    nonisolated private static func adoptionTarget(
        _ item: ClipboardItem, in directory: URL?
    ) -> ClipboardItem {
        guard let directory, item.kind == .image, let path = item.imagePath else { return item }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return ClipboardItem(
            id: item.id, kind: .image, text: nil,
            imagePath: directory.appendingPathComponent(name).path, createdAt: item.createdAt,
            sourceBundleID: item.sourceBundleID, pinnedAt: item.pinnedAt, name: item.name,
            filePaths: item.filePaths)
    }

    nonisolated private static func writeMetadata(
        _ metadata: StoredMetadata?, for item: ClipboardItem, in db: OpaquePointer?
    ) {
        guard let metadata else { return }
        let name = metadata.name.map(boundedName)
        let filePaths = Array(metadata.filePaths.prefix(maximumFilePathCount))
        let representations = boundedRepresentations(metadata.representations)
        let qrPayloads = boundedQRCodes(metadata.qrPayloads)
        if let name, !name.isEmpty, let stmt = prepareStatic(
            db, "INSERT OR REPLACE INTO item_names(item_id, name) VALUES(?1, ?2)"
        ) {
            sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        if !filePaths.isEmpty, let stmt = prepareStatic(
            db, "INSERT INTO item_files(item_id, ordinal, path) VALUES(?1, ?2, ?3)"
        ) {
            for (ordinal, path) in filePaths.enumerated() {
                sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(ordinal))
                sqlite3_bind_text(stmt, 3, path, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
            }
            sqlite3_finalize(stmt)
        }
        if let stmt = prepareStatic(
            db,
            """
            INSERT INTO item_representations(item_id, ordinal, value_index, type_identifier, data)
            VALUES(?1, ?2, ?3, ?4, ?5)
            """
        ) {
            for (ordinal, representation) in representations.enumerated() {
                for (index, data) in representation.values.enumerated() {
                    sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(stmt, 2, Int32(ordinal))
                    sqlite3_bind_int(stmt, 3, Int32(index))
                    sqlite3_bind_text(stmt, 4, representation.typeIdentifier, -1, SQLITE_TRANSIENT)
                    data.withUnsafeBytes { bytes in
                        _ = sqlite3_bind_blob(
                            stmt, 5, bytes.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                    }
                    sqlite3_step(stmt)
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                }
            }
            sqlite3_finalize(stmt)
        }
        if !qrPayloads.isEmpty, let stmt = prepareStatic(
            db, "INSERT INTO item_qr(item_id, ordinal, value, is_url) VALUES(?1, ?2, ?3, ?4)"
        ) {
            for (ordinal, payload) in qrPayloads.enumerated() {
                sqlite3_bind_text(stmt, 1, item.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(ordinal))
                sqlite3_bind_text(stmt, 3, payload.value, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 4, payload.isURL ? 1 : 0)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    /// false leaves the row out, so none ever points into a staging tree about to be discarded.
    nonisolated private static func moveBlob(from source: String?, to destination: String?) -> Bool {
        guard let source, let destination else { return false }
        let from = URL(fileURLWithPath: source)
        let to = URL(fileURLWithPath: destination)
        return (try? FileManager.default.moveItem(at: from, to: to)) != nil
            || (try? FileManager.default.copyItem(at: from, to: to)) != nil
    }

    /// Past the memory window, off-main. `READWRITE` because a WAL reader still writes `-shm`.
    nonisolated static func forEachStoredItem(
        inDatabaseAt url: URL, _ body: (ClipboardItem) -> Void
    ) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return
        }
        defer { sqlite3_close_v2(db) }
        var stmt: OpaquePointer?
        let sql = """
            SELECT id, kind, text, image_path, created_at, source_app, pinned_at
            FROM items ORDER BY rowid
            """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = row(stmt) { body(item) }
        }
    }

    struct StoredMetadata: Sendable {
        let name: String?
        let filePaths: [String]
        let representations: [ClipboardRepresentation]
        let qrPayloads: [ClipboardQRPayload]
    }

    struct StoredEntry: Sendable {
        let item: ClipboardItem
        let metadata: StoredMetadata
    }

    nonisolated static func metadata(
        for itemID: UUID, inDatabaseAt url: URL
    ) -> StoredMetadata {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close_v2(db)
            return StoredMetadata(name: nil, filePaths: [], representations: [], qrPayloads: [])
        }
        defer { sqlite3_close_v2(db) }
        let id = itemID.uuidString
        let name = scalarString(db, "SELECT name FROM item_names WHERE item_id = ?1", id)
        var filePaths: [String] = []
        if let stmt = prepareStatic(
            db, "SELECT path FROM item_files WHERE item_id = ?1 ORDER BY ordinal"
        ) {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            filePaths = readStrings(from: stmt, limit: maximumFilePathCount)
            sqlite3_finalize(stmt)
        }
        var representations: [ClipboardRepresentation] = []
        if let stmt = prepareStatic(
            db,
            """
            SELECT ordinal, value_index, type_identifier, data
            FROM item_representations WHERE item_id = ?1 ORDER BY ordinal, value_index
            """
        ) {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            representations = readRepresentations(from: stmt)
            sqlite3_finalize(stmt)
        }
        var qrPayloads: [ClipboardQRPayload] = []
        if let stmt = prepareStatic(
            db, "SELECT value, is_url FROM item_qr WHERE item_id = ?1 ORDER BY ordinal"
        ) {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            qrPayloads = readQRCodes(from: stmt)
            sqlite3_finalize(stmt)
        }
        return StoredMetadata(
            name: name, filePaths: filePaths, representations: representations,
            qrPayloads: qrPayloads)
    }

    nonisolated private static func row(_ stmt: OpaquePointer?) -> ClipboardItem? {
        guard let idString = columnString(stmt, 0), let id = UUID(uuidString: idString),
            let kindString = columnString(stmt, 1),
            let kind = ClipboardItem.Kind(rawValue: kindString)
        else { return nil }
        return ClipboardItem(
            id: id, kind: kind, text: columnString(stmt, 2), imagePath: columnString(stmt, 3),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            sourceBundleID: columnString(stmt, 5), pinnedAt: columnDate(stmt, 6))
    }

    nonisolated private static func columnDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    nonisolated private static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }

    nonisolated private static func columnData(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        guard let ptr = sqlite3_column_blob(stmt, index) else { return nil }
        return Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, index)))
    }

    nonisolated private static func readRepresentations(
        from stmt: OpaquePointer?
    ) -> [ClipboardRepresentation] {
        var result: [ClipboardRepresentation] = []
        var currentType: String?
        var values: [Data] = []
        var total = 0

        func flush() {
            guard let currentType, !values.isEmpty else { return }
            result.append(ClipboardRepresentation(typeIdentifier: currentType, values: values))
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let type = columnString(stmt, 2), !type.isEmpty else { continue }
            if type != currentType {
                flush()
                guard result.count < maximumRepresentationCount else { break }
                currentType = type
                values = []
            }
            guard values.count < maximumValuesPerRepresentation else { continue }
            let byteCount = Int(sqlite3_column_bytes(stmt, 3))
            guard byteCount <= maximumRepresentationBytes,
                total + byteCount <= maximumRepresentationSetBytes,
                let data = columnData(stmt, 3)
            else { continue }
            values.append(data)
            total += byteCount
            if total == maximumRepresentationSetBytes { break }
        }
        flush()
        return result
    }

    nonisolated private static func readQRCodes(
        from stmt: OpaquePointer?
    ) -> [ClipboardQRPayload] {
        var result: [ClipboardQRPayload] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard result.count < ClipboardQRPayload.maximumCount else { break }
            guard let value = columnString(stmt, 0), !value.isEmpty,
                value.utf8.count <= ClipboardQRPayload.maximumBytes
            else { continue }
            let payload = ClipboardQRPayload(value: value, isURL: sqlite3_column_int(stmt, 1) != 0)
            guard !result.contains(payload) else { continue }
            result.append(payload)
        }
        return result
    }

    nonisolated private static func prepareStatic(
        _ db: OpaquePointer?, _ sql: String
    ) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    nonisolated private static func scalarString(
        _ db: OpaquePointer?, _ sql: String, _ id: String
    ) -> String? {
        guard let stmt = prepareStatic(db, sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return columnString(stmt, 0)
    }

    nonisolated private static func readStrings(
        from stmt: OpaquePointer?, limit: Int
    ) -> [String] {
        var values: [String] = []
        while values.count < limit, sqlite3_step(stmt) == SQLITE_ROW {
            if let value = columnString(stmt, 0) { values.append(value) }
        }
        return values
    }
}
