import XCTest
import Foundation
import CryptoKit
import Darwin
@testable import CacheSSDCore

/// Explicit replay of one retained, generated index. Never scans its former
/// source tree or treats historical source identities as action authorization.
final class VolumeSearchReadonlyReplayTests: XCTestCase {
    func testGeneratedMillionEntryIndexQueriesThroughBoundReadOnlyPage() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DISKWING_RUN_SEARCH_REPLAY_TESTS"] == "1" else {
            throw XCTSkip("Opt in to the generated-index read-only search replay")
        }
        let path = try XCTUnwrap(environment["DISKWING_SEARCH_REPLAY_INDEX"])
        let output = URL(fileURLWithPath: try XCTUnwrap(environment["DISKWING_SEARCH_REPLAY_REPORT"]))
        let databaseURL = URL(fileURLWithPath: path)
        let markerURL = environment["DISKWING_SEARCH_REPLAY_MARKER"].map(URL.init(fileURLWithPath:)) ?? databaseURL.deletingPathExtension().appendingPathExtension("ownership.json")
        let parent = try ReplayDirectory(databaseURL.deletingLastPathComponent())
        let markerParent = try ReplayDirectory(markerURL.deletingLastPathComponent())
        let database = try parent.file(databaseURL.lastPathComponent, maximum: 2_147_483_648)
        let marker = try markerParent.file(markerURL.lastPathComponent, maximum: 1_048_576)
        let markerBytes = try marker.bytes(maximum: 1_048_576)
        let proof = try JSONDecoder().decode(ReplayOwnership.self, from: markerBytes)
        try proof.validate(database: database, path: databaseURL.path)
        let hashStarted = DispatchTime.now().uptimeNanoseconds
        let initialHash = try database.sha256()
        guard initialHash == proof.sha256 else { throw replayFailure() }
        let firstHashSeconds = seconds(since: hashStarted)
        try database.assertCurrent(); try marker.assertCurrent()

        let storageRoot = try VolumeScanRoot(url: databaseURL.deletingLastPathComponent(), isInternal: false, isWritable: true)
        guard storageRoot.volumeUUID.caseInsensitiveCompare(proof.volumeUUID) == .orderedSame else { throw replayFailure() }
        let location = VolumeIndexLocation(url: databaseURL, policy: .externalSSD, storageVolumeUUID: storageRoot.volumeUUID, storageRoot: storageRoot)
        let index = try location.openIndex(createIfMissing: false)
        defer { try? index.close() }
        guard index.metadataLookupOnly else { throw replayFailure() }
        let session = try XCTUnwrap(try index.session(id: proof.sessionID))
        let finishedAt = try XCTUnwrap(session.finishedAt)
        let target = try XCTUnwrap(try index.volumeTarget(sessionID: proof.sessionID))
        let summary = try XCTUnwrap(try index.execute("SELECT * FROM entries WHERE session=? AND path=''", [.text(proof.sessionID.uuidString)]).first)
        let actualEntries = ScanIndex.integer(try index.execute("SELECT COUNT(*) AS count FROM entries WHERE session=?", [.text(proof.sessionID.uuidString)]).first ?? [:], "count")
        guard session.isComplete, session.entryCount == 1_002_003, session.logicalBytes == 52, session.allocatedBytes == 8192,
              actualEntries == 1_002_003, finishedAt >= session.startedAt,
              target.id == proof.targetID, target.displayRoot.path == session.root, target.roots.count == 1,
              target.roots[0].identity.device == proof.treeIdentity.device, target.roots[0].identity.inode == proof.treeIdentity.inode,
              ScanIndex.integer(summary, "files") == 1_001_001, ScanIndex.integer(summary, "logical") == 52,
              ScanIndex.integer(summary, "allocated") == 8192, ScanIndex.integer(summary, "coverage") == 0,
              ScanIndex.integer(summary, "directory") == 1, ScanIndex.integer(summary, "link") == 0 else { throw replayFailure() }
        let baselineRSS = try peakRSS()
        var measurements: [[String: Any]] = []
        let queryStarted = DispatchTime.now().uptimeNanoseconds
        for (label, search) in [("tail-resource", "group1000/file0999"), ("changed-after-pause", "post-pause-added")] {
            let started = DispatchTime.now().uptimeNanoseconds
            let page = try index.page(sessionID: proof.sessionID, search: search, limit: 128)
            let duration = seconds(since: started)
            XCTAssertEqual(page.total, 1); XCTAssertEqual(page.items.count, 1); XCTAssertFalse(page.hasNext)
            let values: [SQLValue] = [.text(proof.sessionID.uuidString), .text("%" + search + "%"), .integer(0)]
            let predicate = " WHERE session=? AND path<>'' AND searchable LIKE ? ESCAPE '\\' AND logical>=?"
            let countPlan = try plan(index, "SELECT COUNT(*) AS count FROM entries NOT INDEXED" + predicate, values)
            let pagePlan = try plan(index, "SELECT * FROM entries NOT INDEXED" + predicate + " ORDER BY logical DESC,name COLLATE NOCASE,path LIMIT ? OFFSET ?", values + [.integer(128), .integer(0)])
            for details in [countPlan, pagePlan] {
                XCTAssertTrue(details.contains { $0.hasPrefix("SCAN entries") })
                XCTAssertFalse(details.contains { $0.contains("USING INDEX") || $0.contains("USING COVERING INDEX") })
            }
            measurements.append(["query": label, "seconds": duration, "total": page.total, "items": page.items.count,
                                 "hasNext": page.hasNext, "countPlan": countPlan, "pagePlan": pagePlan])
            print("Generated read-only replay: \(label) completed in \(duration) seconds")
        }
        let parentPath = session.root + (session.root.hasSuffix("/") ? "" : "/") + "group1000"
        let parentStarted = DispatchTime.now().uptimeNanoseconds
        let last = try index.page(sessionID: proof.sessionID, parent: parentPath, allocatedOrder: true, offset: 999, limit: 128)
        let parentSeconds = seconds(since: parentStarted)
        XCTAssertEqual(last.total, 1000); XCTAssertEqual(last.items.count, 1); XCTAssertFalse(last.hasNext)
        XCTAssertEqual(last.items.first?.name, "file0999")
        let parentValues: [SQLValue] = [.text(proof.sessionID.uuidString), .text("group1000"), .integer(0)]
        let parentPredicate = " WHERE session=? AND path<>'' AND parent=? AND logical>=?"
        let parentCountPlan = try plan(index, "SELECT COUNT(*) AS count FROM entries" + parentPredicate, parentValues)
        let parentPagePlan = try plan(index, "SELECT * FROM entries" + parentPredicate + " ORDER BY allocated DESC,name COLLATE NOCASE,path LIMIT ? OFFSET ?", parentValues + [.integer(128), .integer(999)])
        for details in [parentCountPlan, parentPagePlan] {
            XCTAssertTrue(details.contains { $0.contains("entries_parent") }, details.joined(separator: "; "))
            XCTAssertFalse(details.contains { $0.contains("entries_allocated") })
        }
        measurements.append(["query": "parent-allocated-last-page", "seconds": parentSeconds, "total": last.total,
                             "items": last.items.count, "hasNext": last.hasNext, "offset": last.offset,
                             "countPlan": parentCountPlan, "pagePlan": parentPagePlan])
        let querySeconds = seconds(since: queryStarted)
        let replayRSS = try peakRSS()
        XCTAssertLessThan(replayRSS, 536_870_912)
        try index.close()
        let finalHashStarted = DispatchTime.now().uptimeNanoseconds
        guard try database.sha256() == initialHash, try marker.bytes(maximum: 1_048_576) == markerBytes else { throw replayFailure() }
        let finalHashSeconds = seconds(since: finalHashStarted)
        try database.assertCurrent(); try marker.assertCurrent()
        guard testRun?.failureCount == 0 else { return }
        let report: [String: Any] = [
            "schemaVersion": 1, "qualification": "retained-generated-index-read-only-query-replay",
            "queryChangeSource": "b706651b71c501531bdf651ac20b9c751aadb024", "generatedByEngine": proof.generatedByEngine,
            "databaseSHA256": initialHash, "databaseBytes": database.size, "databaseAndMarkerUnchanged": true,
            "readOnlyBoundOpenIndex": true, "notAuthorizedForActions": true, "sourceTreeTraversed": false,
            "scannerRerun": false, "entries": session.entryCount, "files": 1_001_001,
            "entriesCountedInRetainedDatabase": actualEntries,
            "logicalBytes": session.logicalBytes, "allocatedBytes": session.allocatedBytes, "state": session.state,
            "recordedSessionStartedAt": ISO8601DateFormatter().string(from: session.startedAt),
            "recordedSessionFinishedAt": ISO8601DateFormatter().string(from: finishedAt),
            "recordedSessionScanResumeAggregationSeconds": finishedAt.timeIntervalSince(session.startedAt),
            "queries": measurements, "queryWindowSeconds": querySeconds,
            "initialHashSeconds": firstHashSeconds, "finalHashSeconds": finalHashSeconds,
            "queriesFollowFullDatabaseHashVerification": true,
            "coldFilesystemCacheClaimed": false,
            "processPeakRSSBeforeQueries": baselineRSS, "processPeakRSSAfterQueries": replayRSS,
            "peakRSSIncludesTestRunnerAndHashVerification": true,
            "originalScannerElapsedTimeIncluded": false,
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "date": ISO8601DateFormatter().string(from: Date())
        ]
        let outputParent = try ReplayDirectory(output.deletingLastPathComponent())
        guard output.deletingLastPathComponent().path != databaseURL.deletingLastPathComponent().path else { throw replayFailure() }
        try outputParent.writeNew(JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), name: output.lastPathComponent)
    }
    private func plan(_ index: ScanIndex, _ sql: String, _ values: [SQLValue]) throws -> [String] {
        try index.execute("EXPLAIN QUERY PLAN " + sql, values).map { ScanIndex.string($0, "detail") }
    }
    private func seconds(since value: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds &- value) / 1_000_000_000 }
    private func peakRSS() throws -> Int64 {
        var usage = rusage(); guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw replayFailure() }
        return Int64(usage.ru_maxrss)
    }
}

private struct ReplayOwnership: Decodable {
    struct Identity: Decodable { let device: Int64; let inode: UInt64; let ownerUID: UInt32 }
    let schemaVersion: Int
    let purpose: String
    let notAuthorizedForActions: Bool
    let generatedByEngine: String
    let copyIndex: String
    let copyIdentity: Identity
    let treeIdentity: Identity
    let sha256: String
    let sessionID: UUID
    let targetID: String
    let volumeUUID: String
    let state: String
    let entries: Int
    let logicalBytes: Int64
    let allocatedBytes: Int64
    func validate(database: ReplayFile, path: String) throws {
        let validHash = sha256.utf8.count == 64 && sha256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        guard schemaVersion == 1, purpose == "DiskWing generated volume-index query qualification only", notAuthorizedForActions,
              generatedByEngine == "3e37ce9", copyIndex == path, copyIdentity.ownerUID == getuid(), treeIdentity.ownerUID == getuid(),
              copyIdentity.device == database.device, copyIdentity.inode == database.inode, validHash,
              !volumeUUID.isEmpty, !targetID.isEmpty, state == "complete", entries == 1_002_003,
              logicalBytes == 52, allocatedBytes == 8192 else { throw replayFailure() }
    }
}
private final class ReplayDirectory {
    let descriptor: Int32
    init(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw replayFailure() }
        var current = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard current >= 0 else { throw replayFailure() }
        do {
            for part in url.pathComponents.dropFirst() {
                guard Paths.safeComponent(part) else { throw replayFailure() }
                let next = openat(current, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw replayFailure() }
                close(current); current = next
                var metadata = stat()
                guard fstat(current, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR,
                      metadata.st_flags & UInt32(SF_DATALESS) == 0 else { throw replayFailure() }
            }
            descriptor = current
        } catch { close(current); throw error }
    }
    deinit { close(descriptor) }
    func file(_ name: String, maximum: Int64) throws -> ReplayFile { try ReplayFile(parent: self, name: name, maximum: maximum) }
    func writeNew(_ bytes: Data, name: String) throws {
        guard Paths.safeComponent(name) else { throw replayFailure() }
        let output = openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw replayFailure() }
        let handle = FileHandle(fileDescriptor: output, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: bytes); try handle.synchronize()
    }
}
private final class ReplayFile {
    let parent: ReplayDirectory
    let name: String
    let descriptor: Int32
    private let metadata: stat
    var size: Int64 { Int64(metadata.st_size) }
    var device: Int64 { Int64(metadata.st_dev) }
    var inode: UInt64 { UInt64(metadata.st_ino) }
    init(parent: ReplayDirectory, name: String, maximum: Int64) throws {
        guard Paths.safeComponent(name) else { throw replayFailure() }
        let file = openat(parent.descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw replayFailure() }
        var value = stat()
        guard fstat(file, &value) == 0, value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1,
              value.st_uid == getuid(), value.st_mode & 0o077 == 0, value.st_flags & UInt32(SF_DATALESS) == 0,
              value.st_size >= 0, value.st_size <= maximum else { close(file); throw replayFailure() }
        self.parent = parent; self.name = name; descriptor = file; metadata = value
    }
    deinit { close(descriptor) }
    func assertCurrent() throws {
        var opened = stat(), current = stat()
        guard fstat(descriptor, &opened) == 0, fstatat(parent.descriptor, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              matches(opened), matches(current) else { throw replayFailure() }
    }
    private func matches(_ value: stat) -> Bool {
        value.st_dev == metadata.st_dev && value.st_ino == metadata.st_ino && value.st_uid == metadata.st_uid &&
        value.st_size == metadata.st_size && value.st_mode == metadata.st_mode && value.st_flags == metadata.st_flags && value.st_nlink == 1 &&
        value.st_mtimespec.tv_sec == metadata.st_mtimespec.tv_sec && value.st_mtimespec.tv_nsec == metadata.st_mtimespec.tv_nsec
    }
    func bytes(maximum: Int) throws -> Data {
        try assertCurrent()
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.seek(toOffset: 0)
        guard let bytes = try handle.read(upToCount: maximum + 1), bytes.count <= maximum, Int64(bytes.count) == size else { throw replayFailure() }
        try assertCurrent(); return bytes
    }
    func sha256() throws -> String {
        try assertCurrent()
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.seek(toOffset: 0)
        var digest = SHA256(), readBytes: Int64 = 0, done = false
        while !done {
            try autoreleasepool {
                guard let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty else { done = true; return }
                readBytes += Int64(bytes.count); guard readBytes <= size else { throw replayFailure() }
                digest.update(data: bytes)
            }
        }
        guard readBytes == size else { throw replayFailure() }
        try assertCurrent()
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
private func replayFailure() -> Error { CacheSSDError.message("The retained generated-index replay proof changed or was not authorized for read-only qualification") }
