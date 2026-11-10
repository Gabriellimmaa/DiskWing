import Foundation
import CSQLite
import Darwin

/// Disposable verification workspace, separate from durable recovery journals.
/// Bounds memory while preserving Swift's historical path ordering and JSON bytes.
final class VerificationStore {
    private var db: OpaquePointer?
    private let folder: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var count = 0
    private let maxEntries: Int
    private let maxBytes: Int64
    private let minimumFree: Int64
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(workspace: URL? = nil, maxEntries: Int = 1_000_000, maxBytes: Int64 = 536_870_912, minimumFree: Int64 = 268_435_456) throws {
        let base = workspace ?? ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        self.maxEntries = maxEntries; self.maxBytes = maxBytes; self.minimumFree = minimumFree
        folder = base.appendingPathComponent(".DiskWing-verification-\(UUID().uuidString)")
        encoder.outputFormatting = [.sortedKeys]
        do {
            try FileTree.validateDestination(base)
            guard Volumes.free(at: base) >= minimumFree else { throw Self.failure() }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            var info = stat()
            guard lstat(folder.path, &info) == 0, info.st_mode & 0o077 == 0 else { throw Self.failure() }
            let file = folder.appendingPathComponent("manifest.sqlite")
            let fd = open(file.path, O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC | O_RDWR, 0o600)
            guard fd >= 0 else { throw Self.failure() }; close(fd)
            guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOFOLLOW | SQLITE_OPEN_PRIVATECACHE, nil) == SQLITE_OK else { throw Self.failure() }
            guard sqlite3_create_collation_v2(db, "SWIFTPATH", SQLITE_UTF8, nil, { _, leftCount, left, rightCount, right in
                guard let left, let right else { return leftCount == rightCount ? 0 : leftCount < rightCount ? -1 : 1 }
                let a = String(decoding: UnsafeBufferPointer(start: left.assumingMemoryBound(to: UInt8.self), count: Int(leftCount)), as: UTF8.self)
                let b = String(decoding: UnsafeBufferPointer(start: right.assumingMemoryBound(to: UInt8.self), count: Int(rightCount)), as: UTF8.self)
                return a == b ? 0 : a < b ? -1 : 1
            }, nil) == SQLITE_OK else { throw Self.failure() }
            try sql("PRAGMA journal_mode=DELETE")
            try sql("PRAGMA synchronous=OFF") // Rebuildable scratch only; journals remain durable.
            try sql("PRAGMA cache_size=-4096")
            try sql("PRAGMA temp_store=FILE")
            try sql("CREATE TABLE entries(path TEXT COLLATE SWIFTPATH PRIMARY KEY, depth INTEGER NOT NULL, payload BLOB NOT NULL)")
            try sql("CREATE INDEX entry_depth ON entries(depth DESC)")
            try sql("BEGIN IMMEDIATE")
        } catch {
            if let db { sqlite3_close_v2(db) }; db = nil
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
    deinit {
        if let db { sqlite3_close_v2(db) }
        try? FileManager.default.removeItem(at: folder)
    }
    private static func failure() -> Error { CacheSSDError.message(L10n.text("Não foi possível concluir a conferência dentro dos limites de espaço e itens. A origem foi preservada.")) }
    private func sql(_ text: String) throws {
        guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else { throw Self.failure() }
    }
    private func scalar(_ sql: String) throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw Self.failure() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw Self.failure() }
        return sqlite3_column_int64(statement, 0)
    }
    func add(_ entry: ManifestEntry) throws {
        guard count < maxEntries else { throw Self.failure() }
        let data = try encoder.encode(entry)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO entries VALUES(?,?,?)", -1, &statement, nil) == SQLITE_OK else { throw Self.failure() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, entry.path, -1, transient)
        sqlite3_bind_int(statement, 2, Int32(entry.path.split(separator: "/").count))
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw Self.failure() }
        count += 1
        if count % 256 == 0 { try checkBudget() }
    }
    private func checkBudget() throws {
        guard try scalar("PRAGMA page_count") * scalar("PRAGMA page_size") <= maxBytes,
              Volumes.free(at: folder) >= minimumFree else { throw Self.failure() }
    }
    func forEach(deepestFirst: Bool = false, _ visit: (ManifestEntry, Data) throws -> Void) throws {
        try checkBudget()
        try sql("COMMIT")
        let query = "SELECT payload FROM entries ORDER BY " + (deepestFirst ? "depth DESC, " : "") + "path COLLATE SWIFTPATH"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { throw Self.failure() }
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, let pointer = sqlite3_column_blob(statement, 0) else { throw Self.failure() }
            try autoreleasepool {
                let data = Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 0)))
                try visit(decoder.decode(ManifestEntry.self, from: data), data)
            }
        }
    }
}
