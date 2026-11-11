import XCTest
import Foundation
import Darwin
@testable import CacheSSDCore

final class VolumeScanStorageTests: XCTestCase {
    private var root: URL!
    private var disk: URL!
    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-index-storage-\(UUID().uuidString)")
        disk = root.appendingPathComponent("generated-disk")
        try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func location() throws -> VolumeIndexLocation {
        let volume = VolumeInfo(uuid: IndexStoragePolicy.volumeIdentifier(disk), name: "Generated disk", path: disk.path, totalBytes: 10_000_000_000, freeBytes: 9_000_000_000, isInternal: false, isWritable: true)
        return try IndexStoragePolicy.location(internalDirectory: root.appendingPathComponent("internal"), externalVolume: volume, installationID: "generated", targetID: "generated-target", filesystemType: { _ in "apfs" }, freeBytes: { _ in Int64.max })
    }
    private func descriptors(matching identity: FileIdentity) throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").compactMap(Int32.init).filter { descriptor in
            var metadata = stat()
            return fstat(descriptor, &metadata) == 0 && Int64(metadata.st_dev) == identity.device && UInt64(metadata.st_ino) == identity.inode
        }.count
    }
    func testOpenExistingDoesNotCreateParentsOrAnIndex() throws {
        let selected = try location()
        XCTAssertThrowsError(try selected.openIndex(createIfMissing: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: selected.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: disk.appendingPathComponent("MacCaches").path))
    }
    func testMissingStorageBeforeOpenCannotCreateAReplacementDirectory() throws {
        let selected = try location(), retained = root.appendingPathComponent("offline-disk")
        try FileManager.default.moveItem(at: disk, to: retained)
        XCTAssertThrowsError(try selected.openIndex())
        XCTAssertFalse(FileManager.default.fileExists(atPath: disk.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: retained.path).isEmpty)
    }
    func testReplacementStorageAndWrongUUIDAreRejectedBeforeIndexCreation() throws {
        let selected = try location()
        XCTAssertThrowsError(try selected.openIndex(volumeIdentifier: { _ in "wrong-uuid" }))
        let retained = root.appendingPathComponent("retained-disk")
        try FileManager.default.moveItem(at: disk, to: retained)
        try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
        XCTAssertThrowsError(try selected.openIndex())
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: disk.path).isEmpty)
    }
    func testAnchoredParentsRejectLinksIntroducedAfterLocationSelection() throws {
        let selected = try location(), sibling = root.appendingPathComponent("sibling")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: disk.appendingPathComponent("MacCaches"), withDestinationURL: sibling)
        XCTAssertThrowsError(try selected.openIndex())
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: sibling.path).isEmpty)
    }
    func testQueriesRejectStorageReplacementAndCloseStillReleasesTheOriginal() throws {
        let selected = try location(), index = try selected.openIndex()
        let retained = root.appendingPathComponent("retained-disk")
        try FileManager.default.moveItem(at: disk, to: retained)
        try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
        XCTAssertThrowsError(try index.sessions())
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: disk.path).isEmpty)
        try index.close()
        XCTAssertThrowsError(try index.sessions())
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: disk.path).isEmpty)
    }
    func testQueriesRejectRedirectedIntermediateParentsEvenWhenTheyPointToTheOldObject() throws {
        let selected = try location(), index = try selected.openIndex()
        let original = disk.appendingPathComponent("MacCaches/CacheSSD"), sibling = root.appendingPathComponent("moved-private-parent")
        try FileManager.default.moveItem(at: original, to: sibling)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: sibling)
        XCTAssertThrowsError(try index.sessions())
        try index.close()
    }
    func testExplicitCloseReleasesStorageDescriptorsDespiteRetainedIndexReference() throws {
        let selected = try location(), index = try selected.openIndex()
        let identity = try FileIdentity(selected.url), rootIdentity = selected.canonicalRootIdentity.fileIdentity
        XCTAssertGreaterThan(try descriptors(matching: identity), 0)
        XCTAssertGreaterThan(try descriptors(matching: rootIdentity), 0)
        try index.close()
        XCTAssertEqual(try descriptors(matching: identity), 0)
        XCTAssertEqual(try descriptors(matching: rootIdentity), 0)
        XCTAssertThrowsError(try index.sessions())
        try index.close()
        let reopened = try selected.openIndex(createIfMissing: false)
        XCTAssertTrue(try reopened.sessions().isEmpty)
        try reopened.close()
    }
    func testProductionOpeningPathSupportsVolumeScanAndDurableExistingLookup() throws {
        let selected = try location(), tree = disk.appendingPathComponent("tree")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        for file in 0..<80 { try Data([42]).write(to: tree.appendingPathComponent("file-\(file)")) }
        let target = try VolumeScanTarget.folder(tree)
        let index = try selected.openIndex()
        let paused = try VolumeScanner(home: root, maximumEntriesPerPass: 30).scan(target, index: index, policy: IndexStoragePolicy(maximumBytes: nil, minimumFreeBytes: 0))
        try index.close()
        let existing = try selected.openIndex(createIfMissing: false)
        XCTAssertEqual(try existing.resumableVolumeSession(targetID: target.id), paused.id)
        XCTAssertThrowsError(try existing.execute("CREATE TABLE forbidden(value INTEGER)"))
        try existing.close()
        let writable = try selected.openIndex()
        let complete = try VolumeScanner(home: root).scan(target, index: writable, resumeSessionID: paused.id, policy: IndexStoragePolicy(maximumBytes: nil, minimumFreeBytes: 0))
        XCTAssertFalse(complete.isPartial); XCTAssertEqual(complete.root.fileCount, 80)
        try writable.close()
    }
    func testNativeVolumeUUIDProviderMatchesFoundationForTheGeneratedStorage() throws {
        let expected = try XCTUnwrap(try disk.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString)
        XCTAssertEqual(IndexStoragePolicy.volumeIdentifier(disk).lowercased(), expected.lowercased())
        let system = URL(fileURLWithPath: "/", isDirectory: true)
        let systemUUID = try XCTUnwrap(try system.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString)
        XCTAssertEqual(IndexStoragePolicy.volumeIdentifier(system).lowercased(), systemUUID.lowercased(), "The sealed boot snapshot must retain VolumeInfo's logical identity")
    }
    func testRuntimeUUIDChangesAreCheckedOnQueriesAndDuringScannerWork() throws {
        let selected = try location(), uuid = selected.storageRoot.volumeUUID
        var available = true
        let index = try selected.openIndex(volumeIdentifier: { _ in available ? uuid : "changed-uuid" })
        available = false
        XCTAssertThrowsError(try index.sessions())
        try index.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: selected.url.path))
    }
    func testInternalExistingLookupDoesNotCreateTheMissingStore() throws {
        let missing = root.appendingPathComponent("not-created/store")
        let selected = try IndexStoragePolicy.location(internalDirectory: missing, installationID: "generated", targetID: "test")
        XCTAssertThrowsError(try selected.openIndex(createIfMissing: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("not-created").path))
    }
    func testExistingLookupPreservesFutureVolumeFormatWithoutDDLOrCheckpointWrites() throws {
        let selected = try location(), index = try selected.openIndex()
        try index.execute("UPDATE volume_format SET version=99")
        try index.close()
        let before = try FileTree.hash(selected.url)
        XCTAssertThrowsError(try selected.openIndex(createIfMissing: false))
        XCTAssertEqual(try FileTree.hash(selected.url), before)
        // The generic constructor also refuses this format before any DDL.
        XCTAssertThrowsError(try ScanIndex(url: selected.url))
    }
    func testExistingLookupDoesNotUpgradeAnOlderOuterIndexVersion() throws {
        let selected = try location(), index = try selected.openIndex()
        try index.execute("PRAGMA user_version=2")
        try index.close()
        let before = try FileTree.hash(selected.url)
        XCTAssertThrowsError(try selected.openIndex(createIfMissing: false))
        XCTAssertEqual(try FileTree.hash(selected.url), before)
    }
    func testSystemTemporarySpellingCanOpenAndReopenThePrivateIndex() throws {
        let fixture = Paths.physicalURL(FileManager.default.temporaryDirectory).appendingPathComponent("DiskWing-index-system-alias-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let directory = fixture.appendingPathComponent("new-private-store")
        let selected = try IndexStoragePolicy.location(internalDirectory: directory, installationID: "generated", targetID: "default-temp")
        let rawPrefix = selected.url.path.hasPrefix(selected.storageRoot.url.path + "/")
        XCTAssertTrue(rawPrefix, "Physical URL spelling should remain bound before Foundation normalization")
        let index = try selected.openIndex()
        try index.close()
        let reopened = try selected.openIndex(createIfMissing: false)
        XCTAssertTrue(try reopened.sessions().isEmpty)
        try reopened.close()
        let retained = fixture.appendingPathComponent("retained-store")
        try FileManager.default.moveItem(at: directory, to: retained)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: retained)
        XCTAssertThrowsError(try selected.openIndex(createIfMissing: false), "A real custom symlink remains forbidden even when the target identity matches")
    }
    func testClosedUnmarkedVolumeFilesAreRefusedBeforeConstructorMigration() throws {
        for version in [2, 3] {
            let volume = VolumeInfo(uuid: IndexStoragePolicy.volumeIdentifier(disk), name: "Generated disk", path: disk.path, totalBytes: 10_000_000_000, freeBytes: 9_000_000_000, isInternal: false, isWritable: true)
            let selected = try IndexStoragePolicy.location(internalDirectory: root, externalVolume: volume, installationID: "generated", targetID: "unmarked-\(version)", filesystemType: { _ in "apfs" }, freeBytes: { _ in Int64.max })
            let writer = try selected.openIndex()
            try writer.execute("DROP TABLE volume_format")
            try writer.execute("PRAGMA user_version=\(version)")
            try writer.close()
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: selected.url.path)
            let attribute = Data("preserve-unknown-format".utf8)
            XCTAssertEqual(attribute.withUnsafeBytes { setxattr(selected.url.path, "com.diskwing.generated", $0.baseAddress, attribute.count, 0, XATTR_NOFOLLOW) }, 0)
            func bytes() throws -> [String: Data] {
                var result: [String: Data] = [:]
                // DB and WAL hold durable state. SQLite readers can update
                // readmarks in the mmap-backed volatile wal-index (-shm).
                // Never copy/repair that synchronization state for equality.
                // https://sqlite.org/wal.html (WAL-index and read-only databases)
                for suffix in ["", "-wal"] {
                    let file = URL(fileURLWithPath: selected.url.path + suffix)
                    if FileManager.default.fileExists(atPath: file.path) { result[suffix] = try Data(contentsOf: file) }
                }
                let permissions = try FileManager.default.attributesOfItem(atPath: selected.url.path)[.posixPermissions] as? NSNumber
                result["mode"] = Data(String(permissions?.intValue ?? -1).utf8)
                var copiedAttribute = [UInt8](repeating: 0, count: attribute.count)
                XCTAssertEqual(getxattr(selected.url.path, "com.diskwing.generated", &copiedAttribute, copiedAttribute.count, 0, XATTR_NOFOLLOW), attribute.count)
                result["attribute"] = Data(copiedAttribute)
                return result
            }
            let before = try bytes()
            func assertPreserved() throws {
                let after = try bytes()
                for key in Set(before.keys).union(after.keys).sorted() { XCTAssertEqual(after[key], before[key], "Unknown format must preserve \(key.isEmpty ? "main database" : key)") }
            }
            XCTAssertThrowsError(try ScanIndex(url: selected.url))
            try assertPreserved()
            XCTAssertThrowsError(try selected.openIndex())
            try assertPreserved()
            XCTAssertThrowsError(try selected.openIndex(createIfMissing: false))
            try assertPreserved()
        }
    }
}
