import Foundation
import Darwin
import CSQLite

private let sqlTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct IndexedSession: Codable, Identifiable, Sendable {
    public let id: UUID
    public let root: String
    public let volumeUUID: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let state: String
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let entryCount: Int
    public var isComplete: Bool { state == "complete" }
}

public struct IndexedPage: Sendable {
    public let items: [ScanItem]
    public let total: Int
    public let offset: Int
    public let limit: Int
    public var hasNext: Bool { offset + items.count < total }
}

enum SQLValue { case text(String), integer(Int64), real(Double), null }

/// One bounded connection; callers use a worker task for scans and queries.
public final class ScanIndex: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    public let url: URL
    public init(url: URL = Paths.support.appendingPathComponent("index.sqlite")) throws {
        self.url = url
        guard url.standardizedFileURL == url.resolvingSymlinksInPath() else { throw CacheSSDError.message(L10n.text("O índice local foi redirecionado.")) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK else {
            if let db { sqlite3_close_v2(db) }; self.db = nil
            throw CacheSSDError.message(L10n.text("Não foi possível abrir o índice local."))
        }
        sqlite3_busy_timeout(db, 1000)
        let previousVersion = Self.integer(try execute("PRAGMA user_version").first ?? [:], "user_version")
        guard previousVersion <= 3 else { throw CacheSSDError.message(L10n.text("O índice pertence a uma versão mais recente. Atualize o aplicativo.")) }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        try execute("PRAGMA cache_size=-4096")
        try execute("PRAGMA foreign_keys=ON")
        try execute("""
        CREATE TABLE IF NOT EXISTS sessions(
          id TEXT PRIMARY KEY, root TEXT NOT NULL, volume TEXT NOT NULL,
          started REAL NOT NULL, finished REAL, state TEXT NOT NULL,
          logical INTEGER NOT NULL DEFAULT 0, allocated INTEGER NOT NULL DEFAULT 0,
          entries INTEGER NOT NULL DEFAULT 0);
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS entries(
          session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
          path TEXT NOT NULL, parent TEXT, name TEXT NOT NULL, directory INTEGER NOT NULL,
          link INTEGER NOT NULL, logical INTEGER NOT NULL, allocated INTEGER NOT NULL,
          files INTEGER NOT NULL, category TEXT NOT NULL, issue TEXT, depth INTEGER NOT NULL,
          searchable TEXT NOT NULL, PRIMARY KEY(session,path));
        """)
        try execute("CREATE INDEX IF NOT EXISTS entries_parent ON entries(session,parent,logical DESC)")
        try execute("CREATE INDEX IF NOT EXISTS entries_depth ON entries(session,depth,directory)")
        try execute("CREATE INDEX IF NOT EXISTS entries_size ON entries(session,logical DESC,name COLLATE NOCASE,path)")
        try execute("CREATE INDEX IF NOT EXISTS entries_allocated ON entries(session,allocated DESC,name COLLATE NOCASE,path)")
        try execute("CREATE INDEX IF NOT EXISTS entries_folders ON entries(session,directory,logical DESC)")
        let columns = try execute("PRAGMA table_info(entries)").map { Self.string($0, "name") }
        for name in ["device", "inode", "identitySize", "identityTime"] where !columns.contains(name) {
            try execute("ALTER TABLE entries ADD COLUMN " + name + " INTEGER")
        }
        if !columns.contains("coverage") {
            try execute("ALTER TABLE entries ADD COLUMN coverage INTEGER NOT NULL DEFAULT 0")
        }
        if previousVersion < 3 {
            // Historical issues are stored in the original language, independent
            // of the current interface language. Unknown issues stay conservative.
            try execute("UPDATE entries SET coverage=CASE WHEN issue LIKE '%nuvem%' OR issue LIKE '%parcial%' OR issue LIKE '%limite%' THEN 1 ELSE 2 END WHERE issue IS NOT NULL AND issue NOT LIKE 'Blocos %' AND issue NOT LIKE 'Exibindo os %'")
            try execute("UPDATE sessions SET state='partial' WHERE state='complete' AND id IN (SELECT session FROM entries WHERE link=0 AND coverage<>0)")
            try execute("UPDATE entries SET coverage=1 WHERE directory=1 AND coverage=0 AND session IN (SELECT id FROM sessions WHERE state<>'complete')")
        }
        try execute("CREATE TABLE IF NOT EXISTS snapshots(id TEXT PRIMARY KEY,root TEXT NOT NULL,volume TEXT NOT NULL,time REAL NOT NULL,state TEXT NOT NULL,logical INTEGER NOT NULL,allocated INTEGER NOT NULL,folderComplete INTEGER NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS folder_samples(snapshot TEXT NOT NULL REFERENCES snapshots(id) ON DELETE CASCADE,path TEXT NOT NULL,logical INTEGER NOT NULL,allocated INTEGER NOT NULL,PRIMARY KEY(snapshot,path))")
        if previousVersion < 3 {
            // Old snapshots did not record coverage and their source trees may
            // have expired. Require fresh comparable samples rather than infer it.
            try execute("UPDATE snapshots SET state='partial' WHERE state='complete'")
        }
        try execute("PRAGMA user_version=3")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    deinit { if let db { sqlite3_close_v2(db) } }

    @discardableResult func execute(_ sql: String, _ values: [SQLValue] = []) throws -> [[String: SQLValue]] {
        lock.lock(); defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let number = Int32(index + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, number, text, -1, sqlTransient)
            case .integer(let integer): sqlite3_bind_int64(statement, number, integer)
            case .real(let double): sqlite3_bind_double(statement, number, double)
            case .null: sqlite3_bind_null(statement, number)
            }
        }
        var rows: [[String: SQLValue]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw failure() }
            var row: [String: SQLValue] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let key = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row[key] = .integer(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: row[key] = .real(sqlite3_column_double(statement, column))
                case SQLITE_NULL: row[key] = .null
                default: row[key] = .text(String(cString: sqlite3_column_text(statement, column)))
                }
            }
            rows.append(row)
        }
        return rows
    }
    private func failure() -> Error { CacheSSDError.message(L10n.text("O índice não pôde concluir a operação. Verifique espaço e acesso; os arquivos analisados não foram alterados.")) }
    static func string(_ row: [String: SQLValue], _ key: String) -> String { if case .text(let value) = row[key] { return value }; return "" }
    static func integer(_ row: [String: SQLValue], _ key: String) -> Int64 { if case .integer(let value) = row[key] { return value }; return 0 }
    static func double(_ row: [String: SQLValue], _ key: String) -> Double {
        if case .real(let value) = row[key] { return value }; return Double(integer(row, key))
    }
    public func sessions(limit: Int = 50) throws -> [IndexedSession] {
        try execute("SELECT * FROM sessions ORDER BY started DESC LIMIT ?", [.integer(Int64(max(1, min(limit, 100))))]).compactMap(Self.session)
    }
    public func session(id: UUID) throws -> IndexedSession? { try execute("SELECT * FROM sessions WHERE id=?", [.text(id.uuidString)]).first.flatMap(Self.session) }
    public func item(sessionID: UUID, path: String) throws -> ScanItem? {
        guard let session = try session(id: sessionID), Paths.contains(URL(fileURLWithPath: path), in: URL(fileURLWithPath: session.root)) else { return nil }
        let relative = path == session.root ? "" : String(path.dropFirst(session.root == "/" ? 1 : session.root.count + 1))
        return try execute("SELECT * FROM entries WHERE session=? AND path=?", [.text(sessionID.uuidString),.text(relative)]).first.map { Self.item($0, root: session.root) }
    }
    private static func session(_ row: [String: SQLValue]) -> IndexedSession? {
        guard let id = UUID(uuidString: string(row, "id")) else { return nil }
        let finished = double(row, "finished")
        return IndexedSession(id: id, root: string(row, "root"), volumeUUID: string(row, "volume"), startedAt: Date(timeIntervalSince1970: double(row, "started")), finishedAt: finished > 0 ? Date(timeIntervalSince1970: finished) : nil, state: string(row, "state"), logicalBytes: integer(row, "logical"), allocatedBytes: integer(row, "allocated"), entryCount: Int(integer(row, "entries")))
    }
    public func page(sessionID: UUID, parent: String? = nil, search: String = "", filesOnly: Bool = false,
                     minimumBytes: Int64 = 0, allocatedOrder: Bool = false, offset: Int = 0, limit: Int = 120) throws -> IndexedPage {
        guard let session = try session(id: sessionID) else { throw CacheSSDError.message(L10n.text("Análise não encontrada.")) }
        var conditions = ["session=?", "path<>''"], values: [SQLValue] = [.text(sessionID.uuidString)]
        if let parent {
            let root = URL(fileURLWithPath: session.root)
            let url = URL(fileURLWithPath: parent)
            guard Paths.contains(url, in: root) else { throw CacheSSDError.message(L10n.text("A pasta não pertence a esta análise.")) }
            let relative = parent == session.root ? "" : String(parent.dropFirst(session.root == "/" ? 1 : session.root.count + 1))
            conditions.append("parent=?"); values.append(.text(relative))
        }
        if !search.isEmpty {
            let text = search.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
            conditions.append("searchable LIKE ? ESCAPE '\\'"); values.append(.text("%" + text + "%"))
        }
        if filesOnly { conditions.append("directory=0 AND link=0") }
        conditions.append("logical>=?"); values.append(.integer(max(0, minimumBytes)))
        let condition = conditions.joined(separator: " AND "), count = try execute("SELECT COUNT(*) AS count FROM entries WHERE " + condition, values)
        let safeOffset = max(0, offset), safeLimit = max(1, min(limit, 500))
        let rows = try execute("SELECT * FROM entries WHERE " + condition + " ORDER BY " + (allocatedOrder ? "allocated" : "logical") + " DESC,name COLLATE NOCASE,path LIMIT ? OFFSET ?", values + [.integer(Int64(safeLimit)), .integer(Int64(safeOffset))])
        return IndexedPage(items: rows.map { Self.item($0, root: session.root) }, total: Int(count.first.map { Self.integer($0, "count") } ?? 0), offset: safeOffset, limit: safeLimit)
    }
    private static func item(_ row: [String: SQLValue], root: String, children: [ScanItem] = []) -> ScanItem {
        let relative = string(row, "path"), path = relative.isEmpty ? root : URL(fileURLWithPath: root).appendingPathComponent(relative).path
        let issue = string(row, "issue")
        let identity: FileIdentity?
        if case .integer = row["device"] {
            identity = FileIdentity(device: integer(row,"device"), inode: UInt64(bitPattern: integer(row,"inode")), size: integer(row,"identitySize"), modifiedNanoseconds: integer(row,"identityTime"))
        } else { identity = nil }
        return ScanItem(path: path, name: string(row, "name"), isDirectory: integer(row, "directory") == 1, isSymbolicLink: integer(row, "link") == 1, logicalBytes: integer(row, "logical"), allocatedBytes: integer(row, "allocated"), fileCount: Int(integer(row, "files")), category: ContentCategory(rawValue: string(row, "category")) ?? .unknown, issue: issue.isEmpty ? nil : issue, children: children, fileIdentity: identity, coverage: ScanCoverage(databaseValue: integer(row, "coverage")))
    }
    func begin(root: URL, id: UUID, volume: String, started: Date) throws {
        // Reuse the oldest tree's pages before allocating a third tree. Waiting
        // until finish can exhaust a budget that comfortably fits two trees.
        try execute("DELETE FROM sessions WHERE id IN (SELECT id FROM sessions WHERE root=? ORDER BY started DESC LIMIT -1 OFFSET 1)", [.text(root.path)])
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
        try execute("INSERT INTO sessions(id,root,volume,started,state) VALUES(?,?,?,?,?)", [.text(id.uuidString),.text(root.path),.text(volume),.real(started.timeIntervalSince1970),.text("scanning")])
        try execute("BEGIN IMMEDIATE")
    }
    func add(id: UUID, relative: String, item: ScanItem, depth: Int) throws {
        let parent: SQLValue = relative.isEmpty ? .null : .text(relative.contains("/") ? String(relative[..<relative.lastIndex(of: "/")!]) : "")
        let search = relative.folding(options: [.caseInsensitive,.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        try execute("INSERT INTO entries VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    [.text(id.uuidString),.text(relative),parent,.text(item.name),.integer(item.isDirectory ? 1 : 0),.integer(item.isSymbolicLink ? 1 : 0),
                     .integer(item.logicalBytes),.integer(item.allocatedBytes),.integer(Int64(item.fileCount)),.text(item.category.rawValue),item.issue.map(SQLValue.text) ?? .null,.integer(Int64(depth)),.text(search),
                     item.fileIdentity.map { .integer($0.device) } ?? .null, item.fileIdentity.map { .integer(Int64(bitPattern: $0.inode)) } ?? .null,
                     item.fileIdentity?.size.map(SQLValue.integer) ?? .null, item.fileIdentity?.modifiedNanoseconds.map(SQLValue.integer) ?? .null, .integer(item.coverage.databaseValue)])
    }
    func markCoverage(id: UUID, relative: String, coverage: ScanCoverage, issue: String? = nil) throws {
        try execute("UPDATE entries SET coverage=MAX(coverage,?),issue=COALESCE(?,issue) WHERE session=? AND path=?", [.integer(coverage.databaseValue), issue.map(SQLValue.text) ?? .null, .text(id.uuidString), .text(relative)])
    }
    func finish(id: UUID, depth: Int, logical: Int64, allocated: Int64, files: Int, entries: Int, partial: Bool, cancelled: Bool) throws {
        for level in stride(from: depth, through: 0, by: -1) {
            try execute("""
            UPDATE entries AS node SET
              logical=COALESCE((SELECT SUM(child.logical) FROM entries child WHERE child.session=node.session AND child.parent=node.path),0),
              allocated=COALESCE((SELECT SUM(child.allocated) FROM entries child WHERE child.session=node.session AND child.parent=node.path),0),
              files=COALESCE((SELECT SUM(child.files) FROM entries child WHERE child.session=node.session AND child.parent=node.path),0),
              coverage=CASE
                WHEN node.coverage=2 AND NOT EXISTS(SELECT 1 FROM entries child WHERE child.session=node.session AND child.parent=node.path) THEN 2
                WHEN node.coverage<>0 OR EXISTS(SELECT 1 FROM entries child WHERE child.session=node.session AND child.parent=node.path AND child.link=0 AND child.coverage<>0) THEN 1
                ELSE 0 END
            WHERE node.session=? AND node.depth=? AND node.directory=1 AND node.link=0
            """, [.text(id.uuidString),.integer(Int64(level))])
        }
        try execute("UPDATE entries SET logical=?,allocated=?,files=? WHERE session=? AND path=''", [.integer(logical),.integer(allocated),.integer(Int64(files)),.text(id.uuidString)])
        if partial || cancelled { try markCoverage(id: id, relative: "", coverage: .partial) }
        let rootCoverage = Self.integer(try execute("SELECT coverage FROM entries WHERE session=? AND path=''", [.text(id.uuidString)]).first ?? [:], "coverage")
        try execute("UPDATE sessions SET finished=?,state=?,logical=?,allocated=?,entries=? WHERE id=?", [.real(Date().timeIntervalSince1970),.text(cancelled ? "cancelled" : partial || rootCoverage != 0 ? "partial" : "complete"),.integer(logical),.integer(allocated),.integer(Int64(entries)),.text(id.uuidString)])
        try execute("COMMIT")
        try captureSnapshot(sessionID: id)
        // Keep two full trees per root. Summaries remain independently bounded in Store.
        try execute("DELETE FROM sessions WHERE id IN (SELECT id FROM sessions WHERE root=(SELECT root FROM sessions WHERE id=?) ORDER BY started DESC LIMIT -1 OFFSET 2)", [.text(id.uuidString)])
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }
    func abandon(id: UUID) {
        _ = try? execute("ROLLBACK")
        _ = try? execute("UPDATE sessions SET state='interrupted',finished=? WHERE id=?", [.real(Date().timeIntervalSince1970),.text(id.uuidString)])
    }
    public func report(id: UUID, unreadable: [String] = [], mounts: [String] = [], reachedLimit: Bool = false) throws -> ScanReport {
        guard let session = try session(id: id), let row = try execute("SELECT * FROM entries WHERE session=? AND path=''", [.text(id.uuidString)]).first else { throw CacheSSDError.message(L10n.text("Análise incompleta sem raiz disponível.")) }
        let children = try page(sessionID: id, parent: session.root).items
        let largest = try page(sessionID: id, filesOnly: true, limit: 60).items
        return ScanReport(id: id, root: Self.item(row, root: session.root, children: children), startedAt: session.startedAt, finishedAt: session.finishedAt ?? Date(), examinedEntries: session.entryCount, unreadablePaths: unreadable, skippedMounts: mounts, isCancelled: session.state == "cancelled", reachedLimit: reachedLimit, largestFiles: largest)
    }
    public func byteSize() -> Int64 {
        let pages = Self.integer((try? execute("PRAGMA page_count"))?.first ?? [:], "page_count")
        let size = Self.integer((try? execute("PRAGMA page_size"))?.first ?? [:], "page_size")
        return max(pages * size, [url.path,url.path+"-wal"].reduce(0) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1)[.size] as? NSNumber)?.int64Value ?? 0) })
    }
    public func export(sessionID: UUID, to output: URL, cancellation: CancellationFlag = CancellationFlag()) throws {
        guard output.standardizedFileURL == output.resolvingSymlinksInPath(), !Paths.contains(output, in: url.deletingLastPathComponent()) else { throw CacheSSDError.message(L10n.text("Escolha um destino fora dos registros locais e sem links.")) }
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN DEFERRED")
        defer { _ = try? execute("ROLLBACK") }
        guard let session = try session(id: sessionID) else { throw CacheSSDError.message(L10n.text("Análise não encontrada.")) }
        let temp = output.deletingLastPathComponent().appendingPathComponent(".DiskWing-export-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: temp); defer { try? handle.close(); try? FileManager.default.removeItem(at: temp) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try handle.write(contentsOf: Data("{\"schemaVersion\":2,\"session\":".utf8))
        try handle.write(contentsOf: encoder.encode(session)); try handle.write(contentsOf: Data(",\"entries\":[".utf8))
        var cursor = "", first = true
        while true {
            guard !cancellation.isCancelled else { throw CacheSSDError.message(L10n.text("Exportação cancelada; o relatório anterior foi preservado.")) }
            let rows = try execute("SELECT * FROM entries WHERE session=? AND path>? ORDER BY path LIMIT 500", [.text(sessionID.uuidString),.text(cursor)])
            for row in rows {
                if !first { try handle.write(contentsOf: Data(",".utf8)) }; first = false
                try handle.write(contentsOf: encoder.encode(Self.item(row, root: session.root)))
            }
            guard let last = rows.last else { break }
            cursor = Self.string(last, "path")
        }
        try handle.write(contentsOf: Data("]}".utf8)); try handle.synchronize()
        if FileManager.default.fileExists(atPath: output.path) { _ = try FileManager.default.replaceItemAt(output, withItemAt: temp) }
        else { try FileManager.default.moveItem(at: temp, to: output) }
    }
    private func captureSnapshot(sessionID: UUID) throws {
        guard let session = try session(id: sessionID) else { return }
        let count = try execute("SELECT COUNT(*) AS count FROM entries WHERE session=? AND directory=1", [.text(sessionID.uuidString)])
        let complete = Self.integer(count.first ?? [:], "count") <= 10_000
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("INSERT INTO snapshots VALUES(?,?,?,?,?,?,?,?)", [.text(sessionID.uuidString),.text(session.root),.text(session.volumeUUID),.real((session.finishedAt ?? Date()).timeIntervalSince1970),.text(session.state),.integer(session.logicalBytes),.integer(session.allocatedBytes),.integer(complete ? 1 : 0)])
            try execute("INSERT INTO folder_samples SELECT session,path,logical,allocated FROM entries WHERE session=? AND directory=1 ORDER BY logical DESC LIMIT 10000", [.text(sessionID.uuidString)])
            try execute("DELETE FROM snapshots WHERE id IN (SELECT id FROM snapshots ORDER BY time DESC LIMIT -1 OFFSET 50)")
            try execute("COMMIT")
        } catch { _ = try? execute("ROLLBACK"); throw error }
    }
}

public final class IndexedScanner {
    private let home: URL
    private let maxEntries: Int
    private let maxBytes: Int64
    private let volumeIdentifier: (URL) -> String
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, maxEntries: Int = 1_000_000, maxIndexBytes: Int64 = 536_870_912,
                volumeIdentifier: @escaping (URL) -> String = { (try? $0.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) ?? "" }) {
        self.home = home; self.maxEntries = maxEntries; maxBytes = maxIndexBytes; self.volumeIdentifier = volumeIdentifier
    }
    public func scan(_ requested: URL, index: ScanIndex, cancellation: CancellationFlag = CancellationFlag(), progress: (ScanProgress) -> Void = { _ in }) throws -> ScanReport {
        var rootInfo = stat()
        guard lstat(requested.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR else { throw CacheSSDError.message(L10n.text("Selecione uma pasta real disponível.")) }
        let root = Paths.physicalURL(requested), id = UUID(), started = Date()
        let rootPrefix = root.path == "/" ? "/" : root.path + "/"
        let volume = volumeIdentifier(root)
        let categories = CacheCatalog.all(home: home).map { $0.source.path }
        func category(_ path: String) -> ContentCategory {
            if categories.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return .cache }
            if path.contains("/Library/Developer") || path.contains("/Library/Android") || path.contains("/node_modules/") || path.contains("/.gradle/") { return .developer }
            if path.hasSuffix(".app") || path.contains(".app/") || path.hasSuffix(".photoslibrary") { return .application }
            if path.contains("/Library/") || path.hasPrefix("/System/") || path.hasPrefix("/private/") { return .system }
            if Paths.contains(URL(fileURLWithPath: path), in: home) { return .personal }; return .unknown
        }
        try index.begin(root: root, id: id, volume: volume, started: started)
        var count = 1, logical: Int64 = 0, allocated: Int64 = 0, files = 0, maxDepth = 0, limited = false
        var unreadable: [String] = [], mounts: [String] = [], seen = Set<String>(), last = Date.distantPast
        var enumerationError: Error?
        func relativePath(_ url: URL) -> String? {
            if url.path == root.path { return "" }
            guard url.path.hasPrefix(rootPrefix) else { return nil }
            return String(url.path.dropFirst(rootPrefix.count))
        }
        func markUnavailable(_ url: URL) {
            if unreadable.count < 200 { unreadable.append(url.path) }
            guard let relative = relativePath(url) else { return }
            do { try index.markCoverage(id: id, relative: relative, coverage: .unknown, issue: "Sem acesso; tamanho desconhecido") }
            catch { enumerationError = error }
        }
        do {
            let rootItem = ScanItem(path: root.path, name: root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent, isDirectory: true, isSymbolicLink: false, logicalBytes: 0, allocatedBytes: 0, fileCount: 0, category: category(root.path), issue: nil, children: [])
            try index.add(id: id, relative: "", item: rootItem, depth: 0)
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { url, _ in markUnavailable(url); return true }) else { throw CacheSSDError.message(L10n.text("Não foi possível enumerar a pasta.")) }
            var enumerationDone = false
            while !enumerationDone {
              try autoreleasepool {
               for _ in 0..<256 {
                guard let url = e.nextObject() as? URL else { enumerationDone = true; break }
                if cancellation.isCancelled {
                    if let parent = relativePath(url.deletingLastPathComponent()) { try index.markCoverage(id: id, relative: parent, coverage: .partial) }
                    enumerationDone = true; break
                }
                if Paths.contains(url, in: index.url.deletingLastPathComponent()) { if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { e.skipDescendants() }; continue }
                if count >= maxEntries {
                    if let parent = relativePath(url.deletingLastPathComponent()) { try index.markCoverage(id: id, relative: parent, coverage: .partial) }
                    limited = true; enumerationDone = true; break
                }
                guard url.path.hasPrefix(rootPrefix) else { throw CacheSSDError.message(L10n.text("A leitura saiu do escopo selecionado.")) }
                let relative = String(url.path.dropFirst(rootPrefix.count)), depth = relative.split(separator: "/").count
                if depth > 80 {
                    limited = true
                    if let parent = relativePath(url.deletingLastPathComponent()) { try index.markCoverage(id: id, relative: parent, coverage: .partial) }
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { e.skipDescendants() }; continue
                }
                maxDepth = max(maxDepth, depth); count += 1
                var metadata = stat(), issue: String?, bytes: Int64 = 0, blocks: Int64 = 0
                let valid = lstat(url.path, &metadata) == 0, type = metadata.st_mode & S_IFMT
                let folder = type == S_IFDIR, link = type == S_IFLNK
                if !valid { issue = "Não foi possível ler"; if unreadable.count < 200 { unreadable.append(url.path) }; if folder { e.skipDescendants() } }
                else if metadata.st_dev != rootInfo.st_dev { issue = "Outro volume; analise separadamente"; if mounts.count < 100 { mounts.append(url.path) }; if folder { e.skipDescendants() } }
                else if link { issue = "Link; destino não percorrido" }
                else if type == S_IFREG {
                    bytes = Int64(metadata.st_size)
                    if metadata.st_flags & UInt32(SF_DATALESS) != 0 { issue = "Há conteúdo da nuvem ainda não baixado. A origem será preservada." }
                    let duplicate = metadata.st_nlink > 1 && !seen.insert("\(metadata.st_dev):\(metadata.st_ino)").inserted
                    blocks = duplicate ? 0 : Int64(metadata.st_blocks) * 512
                    if duplicate { issue = "Blocos contados em outro hard link" }
                    logical += bytes; allocated += blocks; files += 1
                } else if !folder { continue }
                let identity = valid && !link ? FileIdentity(device: Int64(metadata.st_dev), inode: UInt64(metadata.st_ino), size: Int64(metadata.st_size), modifiedNanoseconds: Int64(metadata.st_mtimespec.tv_sec) &* 1_000_000_000 &+ Int64(metadata.st_mtimespec.tv_nsec)) : nil
                let item = ScanItem(path: url.path, name: url.lastPathComponent, isDirectory: folder, isSymbolicLink: link, logicalBytes: bytes, allocatedBytes: blocks, fileCount: type == S_IFREG && issue != "Outro volume; analise separadamente" ? 1 : 0, category: category(url.path), issue: issue, children: [], fileIdentity: identity)
                try index.add(id: id, relative: relative, item: item, depth: depth)
                if Date().timeIntervalSince(last) > 0.25 { progress(ScanProgress(entries: count, logicalBytes: logical, currentPath: url.path)); last = Date() }
                if count % 1024 == 0 && (index.byteSize() > maxBytes || Volumes.free(at: index.url.deletingLastPathComponent()) < 268_435_456) {
                    let incomplete = folder ? relative : relativePath(url.deletingLastPathComponent()) ?? ""
                    try index.markCoverage(id: id, relative: incomplete, coverage: .partial)
                    limited = true; enumerationDone = true; break
                }
               }
              }
            }
            if let enumerationError { throw enumerationError }
            try index.finish(id: id, depth: maxDepth, logical: logical, allocated: allocated, files: files, entries: count, partial: limited || !unreadable.isEmpty || !mounts.isEmpty, cancelled: cancellation.isCancelled)
            return try index.report(id: id, unreadable: unreadable, mounts: mounts, reachedLimit: limited)
        } catch { index.abandon(id: id); throw error }
    }
}
