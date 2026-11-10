import Foundation
import Darwin

public struct IndexedChildrenSummary: Sendable {
    public let page: IndexedPage
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let omittedLogicalBytes: Int64
    public let omittedAllocatedBytes: Int64
    public let omittedCount: Int
}

extension ScanIndex {
    func prepareVolumeTables() throws {
        let hasMarker = !(try execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='volume_format'")).isEmpty
        if hasMarker {
            let versions = try execute("SELECT version FROM volume_format")
            guard versions.count == 1, Self.integer(versions[0], "version") == 1 else { throw CacheSSDError.message("O formato do índice de volumes é desconhecido e foi preservado.") }
        } else {
            guard try execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name IN ('volume_targets','volume_queue','volume_sources','volume_hardlinks','volume_ownership','volume_phase') LIMIT 1").isEmpty else { throw CacheSSDError.message("O formato do índice de volumes é desconhecido e foi preservado.") }
            try execute("SAVEPOINT volume_format_creation")
            do {
                try execute("CREATE TABLE volume_format(version INTEGER NOT NULL)")
                try execute("INSERT INTO volume_format VALUES(1)")
                try execute("RELEASE volume_format_creation")
            } catch {
                _ = try? execute("ROLLBACK TO volume_format_creation"); _ = try? execute("RELEASE volume_format_creation"); throw error
            }
        }
        try execute("CREATE TABLE IF NOT EXISTS volume_targets(session TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,targetID TEXT NOT NULL,target TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS volume_queue(session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,rootID TEXT NOT NULL,relative TEXT NOT NULL,state TEXT NOT NULL,identity TEXT,PRIMARY KEY(session,rootID,relative))")
        try execute("CREATE INDEX IF NOT EXISTS volume_queue_state ON volume_queue(session,state,rootID,relative)")
        try execute("CREATE TABLE IF NOT EXISTS volume_sources(session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,path TEXT NOT NULL,rootID TEXT NOT NULL,relative TEXT NOT NULL,directory INTEGER NOT NULL,links INTEGER NOT NULL,blocks INTEGER NOT NULL,device INTEGER NOT NULL,inode INTEGER NOT NULL,identity TEXT NOT NULL,PRIMARY KEY(session,path))")
        try execute("CREATE INDEX IF NOT EXISTS volume_sources_relative ON volume_sources(session,rootID,relative)")
        try execute("CREATE INDEX IF NOT EXISTS volume_sources_inode ON volume_sources(session,device,inode,path)")
        try execute("CREATE TABLE IF NOT EXISTS volume_hardlinks(session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,device INTEGER NOT NULL,inode INTEGER NOT NULL,path TEXT NOT NULL,PRIMARY KEY(session,device,inode))")
        try execute("CREATE TABLE IF NOT EXISTS volume_ownership(session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,path TEXT NOT NULL,rootID TEXT NOT NULL,relative TEXT NOT NULL,identity TEXT,flags INTEGER NOT NULL,links INTEGER NOT NULL,blocks INTEGER NOT NULL,PRIMARY KEY(session,path))")
        try execute("CREATE INDEX IF NOT EXISTS volume_ownership_relative ON volume_ownership(session,rootID,relative)")
        try execute("CREATE TABLE IF NOT EXISTS volume_phase(session TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,phase TEXT NOT NULL)")
    }
    public func volumeTarget(sessionID: UUID) throws -> VolumeScanTarget? {
        try prepareVolumeTables()
        guard Self.integer(try execute("SELECT length(target) size FROM volume_targets WHERE session=?", [.text(sessionID.uuidString)]).first ?? [:], "size") <= 1_048_576 else { throw CacheSSDError.message("O registro da análise excedeu o limite de leitura e foi preservado.") }
        guard let row = try execute("SELECT target FROM volume_targets WHERE session=?", [.text(sessionID.uuidString)]).first else { return nil }
        let target = try JSONDecoder().decode(VolumeScanTarget.self, from: Data(Self.string(row, "target").utf8))
        guard target.schemaVersion == 1 else { throw CacheSSDError.message("A análise pertence a uma versão mais recente e foi preservada.") }
        try target.validateStructure()
        return target
    }
    public func resumableVolumeSession(targetID: String) throws -> UUID? {
        try prepareVolumeTables()
        return try execute("SELECT s.id FROM sessions s JOIN volume_targets t ON s.id=t.session WHERE t.targetID=? AND s.state<>'complete' AND (EXISTS(SELECT 1 FROM volume_queue q WHERE q.session=s.id AND q.state<>'done') OR EXISTS(SELECT 1 FROM volume_phase p WHERE p.session=s.id AND p.phase<>'complete')) ORDER BY s.started DESC LIMIT 1", [.text(targetID)]).first.flatMap { UUID(uuidString: Self.string($0, "id")) }
    }
    public func sourceLocation(sessionID: UUID, path: String) throws -> VolumeSourceLocation? {
        guard let session = try session(id: sessionID), let target = try volumeTarget(sessionID: sessionID), Paths.contains(URL(fileURLWithPath: path), in: URL(fileURLWithPath: session.root)) else { return nil }
        let key = path == session.root ? "" : String(path.dropFirst(session.root == "/" ? 1 : session.root.count + 1))
        guard let row = try execute("SELECT * FROM volume_sources WHERE session=? AND path=?", [.text(sessionID.uuidString), .text(key)]).first,
              let root = target.roots.first(where: { $0.id == Self.string(row, "rootID") }) else { return nil }
        var rootMetadata = stat()
        guard VolumeScanRoot.unredirected(root.url), lstat(root.url.path, &rootMetadata) == 0,
              Int64(rootMetadata.st_dev) == root.identity.device, UInt64(rootMetadata.st_ino) == root.identity.inode else { return nil }
        let relative = Self.string(row, "relative")
        let physical = relative.isEmpty ? root.url : root.url.appendingPathComponent(relative)
        let finderRoot = root.role == .data && root.url.path == DataVolumePaths.dataRoot.path ? URL(fileURLWithPath: "/", isDirectory: true) : target.displayRoot
        let candidate = relative.isEmpty ? finderRoot : finderRoot.appendingPathComponent(relative)
        let url = root.role == .data && VolumeScanner.sameEntry(physical, candidate, allowLink: false) && VolumeScanRoot.unredirected(candidate.deletingLastPathComponent()) ? candidate : physical
        return VolumeSourceLocation(root: root, relativePath: relative, url: url, physicalURL: physical)
    }
    public func childrenSummary(sessionID: UUID, parent: String, allocatedOrder: Bool = true, offset: Int = 0, limit: Int = 120) throws -> IndexedChildrenSummary {
        let page = try page(sessionID: sessionID, parent: parent, allocatedOrder: allocatedOrder, offset: offset, limit: limit)
        guard let session = try session(id: sessionID) else { throw CacheSSDError.message("Análise não encontrada.") }
        let key = parent == session.root ? "" : String(parent.dropFirst(session.root == "/" ? 1 : session.root.count + 1))
        let sum = try execute("SELECT COALESCE(SUM(logical),0) logical,COALESCE(SUM(allocated),0) allocated FROM entries WHERE session=? AND parent=?", [.text(sessionID.uuidString), .text(key)]).first ?? [:]
        let logical = Self.integer(sum, "logical"), allocated = Self.integer(sum, "allocated")
        return IndexedChildrenSummary(page: page, logicalBytes: logical, allocatedBytes: allocated,
            omittedLogicalBytes: max(0, logical - page.items.reduce(0) { $0 + $1.logicalBytes }), omittedAllocatedBytes: max(0, allocated - page.items.reduce(0) { $0 + $1.allocatedBytes }), omittedCount: max(0, page.total - page.items.count))
    }
    func volumeUpsert(session: UUID, relative: String, item: ScanItem) throws {
        var parent = relative.contains("/") ? String(relative[..<relative.lastIndex(of: "/")!]) : ""
        var ancestors: [String] = []
        while !parent.isEmpty {
            if !(try execute("SELECT 1 FROM entries WHERE session=? AND path=?", [.text(session.uuidString), .text(parent)])).isEmpty { break }
            ancestors.append(parent); parent = parent.contains("/") ? String(parent[..<parent.lastIndex(of: "/")!]) : ""
        }
        for key in ancestors.reversed() {
            if try execute("SELECT 1 FROM entries WHERE session=? AND path=?", [.text(session.uuidString), .text(key)]).isEmpty {
                try add(id: session, relative: key, item: ScanItem(path: key, name: key.hasPrefix(VolumeScanner.otherData) && !key.contains("/") ? "Outros dados do volume" : URL(fileURLWithPath: key).lastPathComponent, isDirectory: true, isSymbolicLink: false, logicalBytes: 0, allocatedBytes: 0, fileCount: 0, category: .system, issue: nil, children: []), depth: key.split(separator: "/").count)
            }
        }
        try execute("DELETE FROM entries WHERE session=? AND path=?", [.text(session.uuidString), .text(relative)])
        try execute("DELETE FROM volume_sources WHERE session=? AND path=?", [.text(session.uuidString), .text(relative)])
        try execute("DELETE FROM volume_ownership WHERE session=? AND path=?", [.text(session.uuidString), .text(relative)])
        try add(id: session, relative: relative, item: item, depth: relative.split(separator: "/").count)
    }
    func resetVolumeDirectory(session: UUID, rootID: String, relative: String) throws {
        try execute("SAVEPOINT volume_reset")
        do {
        let prefix = relative.isEmpty ? "" : relative + "/"
        let condition = relative.isEmpty ? "relative<>''" : "substr(relative,1,length(?))=?"
        let correctedArgs: [SQLValue] = [.text(session.uuidString), .text(rootID)] + (relative.isEmpty ? [] : [.text(prefix), .text(prefix)])
        try execute("DELETE FROM entries WHERE session=? AND path IN (SELECT path FROM volume_ownership WHERE session=? AND rootID=? AND \(condition))", [.text(session.uuidString)] + correctedArgs)
        try execute("DELETE FROM volume_sources WHERE session=? AND rootID=? AND \(condition)", correctedArgs)
        try execute("DELETE FROM volume_ownership WHERE session=? AND rootID=? AND \(condition)", correctedArgs)
        try execute("DELETE FROM volume_queue WHERE session=? AND rootID=? AND \(condition)", correctedArgs)
        try execute("UPDATE volume_queue SET state='pending',identity=NULL WHERE session=? AND rootID=? AND relative=?", [.text(session.uuidString), .text(rootID), .text(relative)])
        while let orphan = try execute("SELECT parent FROM entries e WHERE session=? AND parent IS NOT NULL AND parent<>'' AND NOT EXISTS(SELECT 1 FROM entries p WHERE p.session=e.session AND p.path=e.parent) LIMIT 1", [.text(session.uuidString)]).first {
            let key = Self.string(orphan, "parent")
            try volumeUpsert(session: session, relative: key, item: ScanItem(path: key, name: URL(fileURLWithPath: key).lastPathComponent, isDirectory: true, isSymbolicLink: false, logicalBytes: 0, allocatedBytes: 0, fileCount: 0, category: .system, issue: nil, children: []))
        }
            try execute("RELEASE volume_reset")
        } catch {
            _ = try? execute("ROLLBACK TO volume_reset"); _ = try? execute("RELEASE volume_reset"); throw error
        }
    }
    func finalizeVolume(session: UUID, state: String) throws {
        try execute("DELETE FROM volume_hardlinks WHERE session=?", [.text(session.uuidString)])
        try execute("INSERT INTO volume_hardlinks SELECT session,device,inode,MIN(path) FROM volume_sources INDEXED BY volume_sources_inode WHERE session=? AND directory=0 AND links>1 GROUP BY session,device,inode", [.text(session.uuidString)])
        try execute("UPDATE entries SET allocated=COALESCE((SELECT CASE WHEN s.links<=1 OR EXISTS(SELECT 1 FROM volume_hardlinks h WHERE h.session=s.session AND h.device=s.device AND h.inode=s.inode AND h.path=s.path) THEN s.blocks ELSE 0 END FROM volume_sources s WHERE s.session=entries.session AND s.path=entries.path),allocated) WHERE session=? AND directory=0 AND link=0", [.text(session.uuidString)])
        let depth = Int(Self.integer(try execute("SELECT MAX(depth) depth FROM entries WHERE session=?", [.text(session.uuidString)]).first ?? [:], "depth"))
        for level in stride(from: depth, through: 0, by: -1) {
            try execute("""
            UPDATE entries AS n SET logical=COALESCE((SELECT SUM(c.logical) FROM entries c WHERE c.session=n.session AND c.parent=n.path),0),
              allocated=COALESCE((SELECT SUM(c.allocated) FROM entries c WHERE c.session=n.session AND c.parent=n.path),0),
              files=COALESCE((SELECT SUM(c.files) FROM entries c WHERE c.session=n.session AND c.parent=n.path),0),
              coverage=CASE WHEN n.coverage=2 AND NOT EXISTS(SELECT 1 FROM entries c WHERE c.session=n.session AND c.parent=n.path) THEN 2
                WHEN n.coverage<>0 OR EXISTS(SELECT 1 FROM entries c WHERE c.session=n.session AND c.parent=n.path AND c.link=0 AND c.coverage<>0) THEN 1 ELSE 0 END
            WHERE n.session=? AND n.depth=? AND n.directory=1 AND n.link=0
            """, [.text(session.uuidString), .integer(Int64(level))])
            try execute("DELETE FROM entries AS e WHERE e.session=? AND e.depth=? AND e.path<>'' AND e.directory=1 AND NOT EXISTS(SELECT 1 FROM volume_ownership o WHERE o.session=e.session AND o.path=e.path) AND NOT EXISTS(SELECT 1 FROM entries c WHERE c.session=e.session AND c.parent=e.path)", [.text(session.uuidString), .integer(Int64(level))])
        }
        if state != "complete" { try markCoverage(id: session, relative: "", coverage: .partial) }
        let root = try execute("SELECT * FROM entries WHERE session=? AND path=''", [.text(session.uuidString)]).first ?? [:]
        let count = Self.integer(try execute("SELECT COUNT(*) count FROM entries WHERE session=?", [.text(session.uuidString)]).first ?? [:], "count")
        let resultState = state == "complete" && Self.integer(root, "coverage") != 0 ? "partial" : state
        try execute("UPDATE sessions SET state=?,finished=?,logical=?,allocated=?,entries=? WHERE id=?", [.text(resultState), .real(Date().timeIntervalSince1970), .integer(Self.integer(root, "logical")), .integer(Self.integer(root, "allocated")), .integer(count), .text(session.uuidString)])
        try execute("UPDATE volume_phase SET phase=? WHERE session=?", [.text(state == "paused" || state == "cancelled" ? "enumerating" : "complete"), .text(session.uuidString)])
        try execute("PRAGMA wal_checkpoint(PASSIVE)")
    }
}

/// Durable directory work is stored in SQLite. Resumption restarts an unfinished
/// directory and revalidates already indexed identities before trusting totals.
public enum VolumeScanPhase: String, Sendable { case revalidating, resetting, enumerating, aggregating }
public final class VolumeScanner {
    static let otherData = ".DiskWing-Other-Volume-Data"
    private let home: URL
    private let volumeIdentifier: (URL) -> String
    private let freeBytes: (URL) -> Int64
    private let maximumEntriesPerPass: Int?
    private let additionalExcludedRoots: [URL]
    private let phaseChanged: (VolumeScanPhase) -> Void
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, maximumEntriesPerPass: Int? = nil,
                volumeIdentifier: @escaping (URL) -> String = IndexStoragePolicy.volumeIdentifier,
                freeBytes: @escaping (URL) -> Int64 = Volumes.free, excludedRoots: [URL] = [], phaseChanged: @escaping (VolumeScanPhase) -> Void = { _ in }) {
        self.home = home; self.maximumEntriesPerPass = maximumEntriesPerPass; self.volumeIdentifier = volumeIdentifier; self.freeBytes = freeBytes; additionalExcludedRoots = excludedRoots; self.phaseChanged = phaseChanged
    }
    static func sameEntry(_ lhs: URL, _ rhs: URL, allowLink: Bool) -> Bool {
        var a = stat(), b = stat()
        return lstat(lhs.path, &a) == 0 && lstat(rhs.path, &b) == 0 && a.st_dev == b.st_dev && a.st_ino == b.st_ino && (a.st_mode & S_IFMT) == (b.st_mode & S_IFMT) && (allowLink || a.st_mode & S_IFMT != S_IFLNK)
    }
    private func validate(_ root: VolumeScanRoot) throws {
        var metadata = stat()
        guard VolumeScanRoot.unredirected(root.url), lstat(root.url.path, &metadata) == 0,
              Int64(metadata.st_dev) == root.identity.device, UInt64(metadata.st_ino) == root.identity.inode,
              volumeIdentifier(root.url).caseInsensitiveCompare(root.volumeUUID) == .orderedSame else { throw CacheSSDError.message("O volume analisado mudou ou está indisponível. A análise pode ser retomada quando a identidade for confirmada.") }
    }
    private func key(root: VolumeScanRoot, relative: String, target: VolumeScanTarget, metadata: stat? = nil) -> String {
        guard target.isSystemGroup, root.role == .data, !relative.isEmpty else { return relative }
        let physical = root.url.appendingPathComponent(relative), canonical = target.displayRoot.appendingPathComponent(relative)
        var candidate = stat()
        if VolumeScanRoot.unredirected(canonical.deletingLastPathComponent()), lstat(canonical.path, &candidate) == 0 {
            if let metadata {
                if metadata.st_dev == candidate.st_dev && metadata.st_ino == candidate.st_ino && (metadata.st_mode & S_IFMT) == (candidate.st_mode & S_IFMT) { return relative }
            } else if VolumeScanRoot.unredirected(physical.deletingLastPathComponent()), Self.sameEntry(physical, canonical, allowLink: true) { return relative }
        }
        return target.dataNamespace + "/" + relative
    }
    private func directoryDescriptor(root: VolumeScanRoot, relative: String) -> Int32 {
        var descriptor = open(root.url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return -1 }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, Int64(metadata.st_dev) == root.identity.device, UInt64(metadata.st_ino) == root.identity.inode else { close(descriptor); return -1 }
        for part in relative.split(separator: "/", omittingEmptySubsequences: false) where !part.isEmpty {
            guard part != ".", part != "..", !part.contains("\0") else { close(descriptor); return -1 }
            let next = openat(descriptor, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(descriptor)
            guard next >= 0 else { return -1 }
            descriptor = next
            guard fstat(descriptor, &metadata) == 0, Int64(metadata.st_dev) == root.identity.device else { close(descriptor); return -1 }
        }
        return descriptor
    }
    private func metadataAt(root: VolumeScanRoot, relative: String) -> stat? {
        var metadata = stat()
        if relative.isEmpty {
            let descriptor = directoryDescriptor(root: root, relative: "")
            guard descriptor >= 0 else { return nil }; defer { close(descriptor) }
            return fstat(descriptor, &metadata) == 0 ? metadata : nil
        }
        let parent = relative.contains("/") ? String(relative[..<relative.lastIndex(of: "/")!]) : ""
        let name = relative.contains("/") ? String(relative[relative.index(after: relative.lastIndex(of: "/")!)...]) : relative
        let descriptor = directoryDescriptor(root: root, relative: parent)
        guard descriptor >= 0 else { return nil }; defer { close(descriptor) }
        return fstatat(descriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 ? metadata : nil
    }
    private func identity(_ metadata: stat) -> FileIdentity {
        FileIdentity(device: Int64(metadata.st_dev), inode: UInt64(metadata.st_ino), size: Int64(metadata.st_size), modifiedNanoseconds: Int64(metadata.st_mtimespec.tv_sec) &* 1_000_000_000 &+ Int64(metadata.st_mtimespec.tv_nsec))
    }
    private func encoded<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    private func pruneOlderSessions(session: UUID, root: URL, index: ScanIndex) throws {
        var time = Double.greatestFiniteMagnitude, cursor = "~", retainedKnown = false
        while true {
            let more = try autoreleasepool { () throws -> Bool in
                let rows = try index.execute("SELECT s.id,s.started,CASE WHEN length(t.target)<=1048576 THEN t.target ELSE NULL END target FROM sessions s JOIN volume_targets t ON t.session=s.id WHERE s.root=? AND s.id<>? AND (s.started<? OR (s.started=? AND s.id<?)) ORDER BY s.started DESC,s.id DESC LIMIT 128", [.text(root.path), .text(session.uuidString), .real(time), .real(time), .text(cursor)])
                guard let last = rows.last else { return false }
                for row in rows {
                    guard let previous = try? JSONDecoder().decode(VolumeScanTarget.self, from: Data(ScanIndex.string(row, "target").utf8)), previous.schemaVersion == 1, (try? previous.validateStructure()) != nil else { continue }
                    if !retainedKnown { retainedKnown = true; continue }
                    phaseChanged(.resetting)
                    try index.execute("DELETE FROM sessions WHERE id=?", [.text(ScanIndex.string(row, "id"))])
                }
                time = ScanIndex.double(last, "started"); cursor = ScanIndex.string(last, "id")
                return true
            }
            if !more { break }
        }
    }
    private func reset(session: UUID, rootID: String, relative: String, index: ScanIndex) throws {
        phaseChanged(.resetting)
        defer { phaseChanged(.revalidating) }
        try index.resetVolumeDirectory(session: session, rootID: rootID, relative: relative)
    }
    private func revalidate(session: UUID, target: VolumeScanTarget, index: ScanIndex, cancellation: CancellationFlag, progress: (ScanProgress) -> Void) throws {
        var checked = 0
        var jobCursor = ""
        while true {
          let more = try autoreleasepool { () throws -> Bool in
            try index.checkVolumeWork()
            let jobs = try index.execute("SELECT *,rootID||char(10)||relative cursor FROM volume_queue WHERE session=? AND state='done' AND rootID||char(10)||relative>? ORDER BY rootID,relative LIMIT 256", [.text(session.uuidString), .text(jobCursor)])
            guard let last = jobs.last else { return false }
            for job in jobs {
                if cancellation.isCancelled { throw VolumeScanStop.cancelled }
                guard let root = target.roots.first(where: { $0.id == ScanIndex.string(job, "rootID") }) else { throw CacheSSDError.message("A análise não corresponde aos volumes selecionados.") }
                let relative = ScanIndex.string(job, "relative")
                let previous = try? JSONDecoder().decode(FileIdentity.self, from: Data(ScanIndex.string(job, "identity").utf8))
                if previous == nil || metadataAt(root: root, relative: relative).map(identity) != previous { try reset(session: session, rootID: root.id, relative: relative, index: index) }
                checked += 1
                if checked % 64 == 0 { progress(ScanProgress(entries: checked, logicalBytes: 0, currentPath: root.url.appendingPathComponent(relative).path)); try index.checkVolumeWork() }
            }
            jobCursor = ScanIndex.string(last, "cursor")
            return true
          }
          if !more { break }
        }
        var cursor = ""
        while true {
          let more = try autoreleasepool { () throws -> Bool in
            try index.checkVolumeWork()
            let rows = try index.execute("SELECT s.*,e.directory,e.link FROM volume_ownership s JOIN entries e ON s.session=e.session AND s.path=e.path WHERE s.session=? AND s.path>? ORDER BY s.path LIMIT 256", [.text(session.uuidString), .text(cursor)])
            guard let last = rows.last else { return false }
            for row in rows {
                if cancellation.isCancelled { throw VolumeScanStop.cancelled }
                guard let root = target.roots.first(where: { $0.id == ScanIndex.string(row, "rootID") }) else { throw CacheSSDError.message("A análise não corresponde aos volumes selecionados.") }
                let relative = ScanIndex.string(row, "relative")
                let previous = try? JSONDecoder().decode(FileIdentity.self, from: Data(ScanIndex.string(row, "identity").utf8))
                let metadata = metadataAt(root: root, relative: relative), current = metadata.map(identity)
                let sameDirectory = ScanIndex.integer(row, "directory") == 1 && metadata.map { $0.st_mode & S_IFMT == S_IFDIR } == true && current?.device == previous?.device && current?.inode == previous?.inode
                let mappingChanged = metadata.map { key(root: root, relative: relative, target: target, metadata: $0) != ScanIndex.string(row, "path") } ?? true
                if metadata == nil || current != previous || metadata.map({ Int64($0.st_nlink) != ScanIndex.integer(row, "links") || Int64($0.st_flags) != ScanIndex.integer(row, "flags") || (ScanIndex.integer(row, "directory") == 0 && Int64($0.st_blocks) * 512 != ScanIndex.integer(row, "blocks")) }) == true || mappingChanged {
                    let directory = sameDirectory && !mappingChanged ? relative : relative.contains("/") ? String(relative[..<relative.lastIndex(of: "/")!]) : ""
                    try reset(session: session, rootID: root.id, relative: directory, index: index)
                    try index.execute("INSERT OR REPLACE INTO volume_queue VALUES(?,?,?,'pending',NULL)", [.text(session.uuidString), .text(root.id), .text(directory)])
                }
                checked += 1
                if checked % 64 == 0 { progress(ScanProgress(entries: checked, logicalBytes: 0, currentPath: root.url.appendingPathComponent(relative).path)); try index.checkVolumeWork() }
            }
            cursor = ScanIndex.string(last, "path")
            return true
          }
          if !more { break }
        }
        try index.execute("UPDATE volume_queue SET state='pending',identity='restart' WHERE session=? AND state IN ('scanning','blocked')", [.text(session.uuidString)])
        try index.execute("UPDATE entries SET coverage=0 WHERE session=? AND directory=1 AND issue IS NULL", [.text(session.uuidString)])
    }
    public func scan(_ requestedTarget: VolumeScanTarget, index: ScanIndex, resumeSessionID: UUID? = nil, policy: IndexStoragePolicy = .internalStorage,
                     cancellation: CancellationFlag = CancellationFlag(), progress: (ScanProgress) -> Void = { _ in }) throws -> ScanReport {
        guard requestedTarget.schemaVersion == 1 else { throw CacheSSDError.message("A análise pertence a uma versão mais recente e foi preservada.") }
        try requestedTarget.validateStructure()
        var target = requestedTarget
        for root in target.roots { try validate(root) }
        try index.prepareVolumeTables()
        let session = resumeSessionID ?? UUID()
        if let resumeSessionID {
            guard let previous = try index.volumeTarget(sessionID: resumeSessionID), previous.id == target.id,
                  Set(previous.roots.map(\.volumeUUID)) == Set(target.roots.map(\.volumeUUID)),
                  previous.roots.allSatisfy({ old in target.roots.contains { $0.volumeUUID == old.volumeUUID && $0.identity.inode == old.identity.inode } }) else { throw CacheSSDError.message("A análise não corresponde aos volumes selecionados.") }
            target = try VolumeScanTarget(id: target.id, name: target.name, roots: target.roots, displayRoot: target.displayRoot, dataNamespace: previous.dataNamespace)
            var collision = stat()
            guard !target.isSystemGroup || lstat(target.displayRoot.appendingPathComponent(target.dataNamespace).path, &collision) != 0 && errno == ENOENT else { throw CacheSSDError.message("O namespace da análise passou a existir no volume. Inicie uma nova análise; o índice anterior foi preservado.") }
        } else {
            var collision = stat()
            guard !target.isSystemGroup || lstat(target.displayRoot.appendingPathComponent(target.dataNamespace).path, &collision) != 0 && errno == ENOENT else { throw CacheSSDError.message("O namespace da análise passou a existir no volume. Inicie uma nova análise; o índice anterior foi preservado.") }
            // Create only the bounded resumable header here. Retention can
            // delete millions of rows, so it belongs inside guarded SQL work.
            try index.execute("BEGIN IMMEDIATE")
            do {
                try index.execute("INSERT INTO sessions(id,root,volume,started,state) VALUES(?,?,?,?,?)", [.text(session.uuidString), .text(target.displayRoot.path), .text(target.id), .real(Date().timeIntervalSince1970), .text("scanning")])
                try index.add(id: session, relative: "", item: ScanItem(path: target.displayRoot.path, name: target.name, isDirectory: true, isSymbolicLink: false, logicalBytes: 0, allocatedBytes: 0, fileCount: 0, category: .unknown, issue: nil, children: []), depth: 0)
                try index.execute("INSERT INTO volume_targets VALUES(?,?,?)", [.text(session.uuidString), .text(target.id), .text(try encoded(target))])
                try index.execute("INSERT INTO volume_phase VALUES(?,'enumerating')", [.text(session.uuidString)])
                for root in target.roots { try index.execute("INSERT INTO volume_queue VALUES(?,?,?,'pending',NULL)", [.text(session.uuidString), .text(root.id), .text("")]) }
                try index.execute("COMMIT")
            } catch { index.abandon(id: session); throw error }
        }
        func resourcesAllowed() -> Bool { (policy.maximumBytes.map { index.physicalDatabaseBytes() < $0 } ?? true) && freeBytes(index.url.deletingLastPathComponent()) >= policy.minimumFreeBytes }
        do {
          return try index.withVolumeWorkChecks(cancellation: cancellation, allowed: resourcesAllowed) {
            try pruneOlderSessions(session: session, root: target.displayRoot, index: index)
            if resumeSessionID != nil {
                phaseChanged(.revalidating)
                try index.execute("UPDATE volume_phase SET phase='revalidating' WHERE session=?", [.text(session.uuidString)])
                try revalidate(session: session, target: target, index: index, cancellation: cancellation, progress: progress)
                try index.execute("UPDATE sessions SET root=?,state='scanning' WHERE id=?", [.text(target.displayRoot.path), .text(session.uuidString)])
                try index.execute("UPDATE volume_targets SET target=? WHERE session=?", [.text(try encoded(target)), .text(session.uuidString)])
            }
            phaseChanged(.enumerating)
            try index.execute("UPDATE volume_phase SET phase='enumerating' WHERE session=?", [.text(session.uuidString)])
        var read = 0, observedBytes: Int64 = 0, paused = false
        let exclusions = [index.url.deletingLastPathComponent(), home.appendingPathComponent("Library/Application Support/CacheSSD")] + additionalExcludedRoots
        let excludedRoots = exclusions.flatMap { [$0] + (DataVolumePaths.alias(of: $0).map { [$0] } ?? []) }
        let cacheSources = CacheCatalog.all(home: home).map { $0.source.path }
        func storageAvailable() -> Bool { (policy.maximumBytes.map { index.byteSize() < $0 } ?? true) && freeBytes(index.url.deletingLastPathComponent()) >= policy.minimumFreeBytes }
        while !cancellation.isCancelled {
          let keepScanning = try autoreleasepool { () throws -> Bool in
            guard storageAvailable(), maximumEntriesPerPass.map({ read < $0 }) ?? true else { paused = true; return false }
            guard let job = try index.execute("SELECT * FROM volume_queue WHERE session=? AND state='pending' ORDER BY rootID,relative LIMIT 1", [.text(session.uuidString)]).first else { return false }
            guard let root = target.roots.first(where: { $0.id == ScanIndex.string(job, "rootID") }) else { throw CacheSSDError.message("A análise não corresponde aos volumes selecionados.") }
            try validate(root)
            let directoryRelative = ScanIndex.string(job, "relative"), directory = directoryRelative.isEmpty ? root.url : root.url.appendingPathComponent(directoryRelative)
            if ScanIndex.string(job, "identity") == "restart" { try reset(session: session, rootID: root.id, relative: directoryRelative, index: index); phaseChanged(.enumerating) }
            try index.execute("UPDATE volume_queue SET state='scanning' WHERE session=? AND rootID=? AND relative=?", [.text(session.uuidString), .text(root.id), .text(directoryRelative)])
            let storedSource = try index.execute("SELECT * FROM volume_sources WHERE session=? AND rootID=? AND relative=? LIMIT 1", [.text(session.uuidString), .text(root.id), .text(directoryRelative)]).first
            let storedKey = storedSource.map { ScanIndex.string($0, "path") }
            let directoryKey = storedKey ?? key(root: root, relative: directoryRelative, target: target)
            try index.execute("UPDATE entries SET coverage=0,issue=NULL WHERE session=? AND path=? AND directory=1", [.text(session.uuidString), .text(directoryKey)])
            if excludedRoots.contains(where: { Paths.contains(directory, in: $0) }) {
                try index.markCoverage(id: session, relative: directoryKey, coverage: .unknown, issue: "Registros privados do DiskWing; conteúdo excluído da análise")
                try index.execute("UPDATE volume_queue SET state='done' WHERE session=? AND rootID=? AND relative=?", [.text(session.uuidString), .text(root.id), .text(directoryRelative)])
                return true
            }
            let descriptor = directoryDescriptor(root: root, relative: directoryRelative)
            guard descriptor >= 0, let stream = fdopendir(descriptor) else {
                if descriptor >= 0 { close(descriptor) }
                try index.markCoverage(id: session, relative: directoryKey, coverage: .unknown, issue: "Sem acesso; tamanho desconhecido")
                try index.execute("UPDATE volume_queue SET state='blocked' WHERE session=? AND rootID=? AND relative=?", [.text(session.uuidString), .text(root.id), .text(directoryRelative)])
                return true
            }
            defer { closedir(stream); _ = try? index.execute("ROLLBACK") }
            var opened = stat()
            guard fstat(dirfd(stream), &opened) == 0 else { throw CacheSSDError.message("Não foi possível confirmar a pasta analisada.") }
            let directoryIdentity = FileIdentity(device: Int64(opened.st_dev), inode: UInt64(opened.st_ino), size: Int64(opened.st_size), modifiedNanoseconds: Int64(opened.st_mtimespec.tv_sec) &* 1_000_000_000 &+ Int64(opened.st_mtimespec.tv_nsec))
            if let storedSource, ScanIndex.integer(storedSource, "device") != directoryIdentity.device || UInt64(bitPattern: ScanIndex.integer(storedSource, "inode")) != directoryIdentity.inode {
                try index.markCoverage(id: session, relative: directoryKey, coverage: .partial, issue: "A pasta mudou ou não pôde ser lida completamente. Retome para conferir novamente.")
                try index.execute("UPDATE volume_queue SET state='blocked' WHERE session=? AND rootID=? AND relative=?", [.text(session.uuidString), .text(root.id), .text(directoryRelative)])
                return true
            }
            try index.execute("BEGIN IMMEDIATE")
            var completed = true, enumerationFailed = false
            while true {
                errno = 0
                guard let entry = readdir(stream) else { if errno != 0 { enumerationFailed = true }; break }
              let keepReading = try autoreleasepool { () throws -> Bool in
                let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(validatingUTF8: $0) } }
                guard let name else { enumerationFailed = true; return true }
                if name == "." || name == ".." { return true }
                if cancellation.isCancelled || read % 64 == 0 && !storageAvailable() || maximumEntriesPerPass.map({ read >= $0 }) == true { completed = false; paused = !cancellation.isCancelled; return false }
                let relative = directoryRelative.isEmpty ? name : directoryRelative + "/" + name
                let source = directory.appendingPathComponent(name)
                var metadata = stat(); read += 1
                let valid = fstatat(dirfd(stream), name, &metadata, AT_SYMLINK_NOFOLLOW) == 0, type = metadata.st_mode & S_IFMT
                let displayKey = key(root: root, relative: relative, target: target, metadata: valid ? metadata : nil)
                let folder = type == S_IFDIR, link = type == S_IFLNK
                var issue: String?, coverage: ScanCoverage = .complete, logical: Int64 = 0, blocks: Int64 = 0, files = 0
                if !valid { issue = "Não foi possível ler"; coverage = .unknown }
                else if excludedRoots.contains(where: { Paths.contains(source, in: $0) }) {
                    issue = "Registros privados do DiskWing; conteúdo excluído da análise"; coverage = .unknown
                } else if Int64(metadata.st_dev) != root.identity.device {
                    let member = target.roots.contains { other in
                        other.id != root.id && other.identity.device == Int64(metadata.st_dev) && (Self.sameEntry(source, other.url, allowLink: false) || Self.sameEntry(source, other.url.appendingPathComponent(relative), allowLink: false))
                    }
                    if member { return true }
                    issue = "Outro volume; analise separadamente"; coverage = .unknown
                } else if link { issue = "Link; destino não percorrido"; coverage = .unknown }
                else if type == S_IFREG {
                    logical = Int64(metadata.st_size); blocks = Int64(metadata.st_blocks) * 512; files = 1
                    if metadata.st_flags & UInt32(SF_DATALESS) != 0 { issue = "Há conteúdo da nuvem ainda não baixado. A origem será preservada."; coverage = .partial }
                } else if !folder { issue = "Arquivo especial; conteúdo não percorrido"; coverage = .unknown }
                let identity = valid && !link ? FileIdentity(device: Int64(metadata.st_dev), inode: UInt64(metadata.st_ino), size: Int64(metadata.st_size), modifiedNanoseconds: Int64(metadata.st_mtimespec.tv_sec) &* 1_000_000_000 &+ Int64(metadata.st_mtimespec.tv_nsec)) : nil
                let category = IndexedScanner.category(source.path, home: home, cacheSources: cacheSources)
                let item = ScanItem(path: source.path, name: name, isDirectory: folder, isSymbolicLink: link, logicalBytes: logical, allocatedBytes: blocks, fileCount: files, category: category, issue: issue, children: [], fileIdentity: identity, coverage: coverage)
                try index.volumeUpsert(session: session, relative: displayKey, item: item)
                let trackedIdentity = valid ? self.identity(metadata) : nil
                try index.execute("INSERT OR REPLACE INTO volume_ownership VALUES(?,?,?,?,?,?,?,?)", [.text(session.uuidString), .text(displayKey), .text(root.id), .text(relative), try trackedIdentity.map { .text(try encoded($0)) } ?? .null, .integer(Int64(metadata.st_flags)), .integer(Int64(metadata.st_nlink)), .integer(Int64(metadata.st_blocks) * 512)])
                if let identity, coverage == .complete || type == S_IFREG && coverage == .partial {
                    try index.execute("INSERT OR REPLACE INTO volume_sources VALUES(?,?,?,?,?,?,?,?,?,?)", [.text(session.uuidString), .text(displayKey), .text(root.id), .text(relative), .integer(folder ? 1 : 0), .integer(Int64(metadata.st_nlink)), .integer(blocks), .integer(identity.device), .integer(Int64(bitPattern: identity.inode)), .text(try encoded(identity))])
                }
                if folder && coverage == .complete { try index.execute("INSERT OR IGNORE INTO volume_queue VALUES(?,?,?,'pending',NULL)", [.text(session.uuidString), .text(root.id), .text(relative)]) }
                observedBytes += logical
                if read % 64 == 0 { progress(ScanProgress(entries: read, logicalBytes: observedBytes, currentPath: source.path)) }
                if read % 256 == 0 { try index.execute("COMMIT"); try index.execute("BEGIN IMMEDIATE") }
                return true
              }
              if !keepReading { break }
            }
            if completed {
                let stable = (try? FileIdentity(directory)) == directoryIdentity
                let state = stable && !enumerationFailed ? "done" : "blocked"
                try index.execute("UPDATE volume_queue SET state=?,identity=? WHERE session=? AND rootID=? AND relative=?", [.text(state), .text(try encoded(directoryIdentity)), .text(session.uuidString), .text(root.id), .text(directoryRelative)])
                if stable {
                    try index.execute("UPDATE volume_sources SET identity=?,links=?,device=?,inode=? WHERE session=? AND rootID=? AND relative=? AND directory=1", [.text(try encoded(directoryIdentity)), .integer(Int64(opened.st_nlink)), .integer(directoryIdentity.device), .integer(Int64(bitPattern: directoryIdentity.inode)), .text(session.uuidString), .text(root.id), .text(directoryRelative)])
                    try index.execute("UPDATE entries SET device=?,inode=?,identitySize=?,identityTime=? WHERE session=? AND path=? AND directory=1", [.integer(directoryIdentity.device), .integer(Int64(bitPattern: directoryIdentity.inode)), directoryIdentity.size.map(SQLValue.integer) ?? .null, directoryIdentity.modifiedNanoseconds.map(SQLValue.integer) ?? .null, .text(session.uuidString), .text(directoryKey)])
                    try index.execute("UPDATE volume_ownership SET identity=?,flags=?,links=?,blocks=? WHERE session=? AND rootID=? AND relative=?", [.text(try encoded(directoryIdentity)), .integer(Int64(opened.st_flags)), .integer(Int64(opened.st_nlink)), .integer(Int64(opened.st_blocks) * 512), .text(session.uuidString), .text(root.id), .text(directoryRelative)])
                }
                if state == "blocked" { try index.markCoverage(id: session, relative: directoryKey, coverage: .partial, issue: "A pasta mudou ou não pôde ser lida completamente. Retome para conferir novamente.") }
            } else {
                try index.markCoverage(id: session, relative: directoryKey, coverage: .partial, issue: "Análise pausada; retome para concluir esta pasta.")
            }
            try index.execute("COMMIT")
            return completed
          }
          if !keepScanning { break }
        }
        let outstanding = ScanIndex.integer(try index.execute("SELECT COUNT(*) count FROM volume_queue WHERE session=? AND state<>'done'", [.text(session.uuidString)]).first ?? [:], "count")
        phaseChanged(.aggregating)
        try index.execute("UPDATE volume_phase SET phase='aggregating' WHERE session=?", [.text(session.uuidString)])
        try index.finalizeVolume(session: session, state: cancellation.isCancelled ? "cancelled" : paused ? "paused" : outstanding > 0 ? "partial" : "complete")
        return try index.report(id: session, reachedLimit: paused || outstanding > 0)
          }
        } catch let stop as VolumeScanStop {
            _ = try? index.execute("ROLLBACK")
            let state: String
            switch stop { case .cancelled: state = "cancelled"; case .storage: state = "paused" }
            try index.execute("UPDATE sessions SET state=?,finished=? WHERE id=?", [.text(state), .real(Date().timeIntervalSince1970), .text(session.uuidString)])
            try index.markCoverage(id: session, relative: "", coverage: .partial)
            try index.execute("UPDATE volume_phase SET phase='aggregating' WHERE session=? AND phase='complete'", [.text(session.uuidString)])
            return try index.report(id: session, reachedLimit: true)
        }
    }
}
