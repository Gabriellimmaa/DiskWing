import XCTest
import Foundation
import Darwin
@testable import CacheSSDCore

final class RecoveryScopeTests: XCTestCase {
    struct Fixture {
        let root: URL; let session: URL; let home: URL; let source: URL; let copy: URL; let sibling: URL; let store: Store
        var journal: OperationJournal
        var name: String { "operation-\(journal.id.uuidString).json" }
        func manager() -> RecoveryManager { RecoveryManager(store: store, home: home, permittedRoot: session) }
    }
    func fixture(parent requestedParent: URL? = nil) throws -> Fixture {
        let parent = requestedParent ?? ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        let root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-recovery-scope-\(UUID().uuidString)")
        let session = root.appendingPathComponent("session"), home = session.appendingPathComponent("home"), source = home.appendingPathComponent("Downloads/recovered.txt")
        let store = Store(base: session.appendingPathComponent("support")), copy = session.appendingPathComponent("copy.txt"), sibling = root.appendingPathComponent("sibling.txt")
        let fm = FileManager.default
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("generated sample".utf8).write(to: source)
        try FileTree.copyItem(source, to: copy)
        var journal = try OperationJournal(kind: "personalMove", source: source, destination: copy)
        journal.phase = .interrupted; journal.sourceDigest = try FileTree.digest(source); journal.destinationDigest = journal.sourceDigest
        let name = "operation-\(journal.id.uuidString).json"
        try store.writeDurably(journal, name: name)
        try fm.removeItem(at: source)
        try Data("generated sibling secret".utf8).write(to: sibling)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Fixture(root: root, session: session, home: home, source: source, copy: copy, sibling: sibling, store: store, journal: journal)
    }
    func testReloadedJournalCannotReadSiblingFixtureAfterAssessment() throws {
        var f = try fixture()
        let manager = f.manager()
        XCTAssertTrue(try XCTUnwrap(manager.pending().first).canRestoreSource)
        f.journal.destination = f.sibling.path; f.journal.destinationDigest = try FileTree.digest(f.sibling)
        try f.store.writeDurably(f.journal, name: f.name)
        let record = try Data(contentsOf: f.store.base.appendingPathComponent(f.name))
        XCTAssertThrowsError(try manager.restoreSource(id: f.journal.id))
        XCTAssertThrowsError(try manager.keepCopiesAndResolve(id: f.journal.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.path))
        XCTAssertFalse(try XCTUnwrap(manager.pending().first).canRestoreSource)
        XCTAssertEqual(try Data(contentsOf: f.store.base.appendingPathComponent(f.name)), record)
        XCTAssertEqual(try String(contentsOf: f.sibling), "generated sibling secret")
    }
    func testScopedRecoveryStillRestoresGeneratedCopyAndKeepsBothRecordsCompatible() throws {
        let f = try fixture(), manager = f.manager()
        try manager.restoreSource(id: f.journal.id)
        XCTAssertEqual(try FileTree.digest(f.source), try FileTree.digest(f.copy))
        XCTAssertEqual(f.store.operations().first?.phase, .resolved)
        XCTAssertEqual(try String(contentsOf: f.sibling), "generated sibling secret")
        XCTAssertTrue(RecoveryManager(store: f.store, home: f.home).pending().isEmpty)
    }
    func testScopedRecoveryAcceptsPhysicalAndStandardizedSystemTemporaryPaths() throws {
        for standardizedSource in [false, true] {
            let f = try fixture(parent: FileManager.default.temporaryDirectory)
            if standardizedSource {
                let file = f.store.base.appendingPathComponent(f.name)
                var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
                value["source"] = f.source.deletingLastPathComponent().standardizedFileURL.appendingPathComponent(f.source.lastPathComponent).path
                try JSONSerialization.data(withJSONObject: value).write(to: file)
            }
            let manager = RecoveryManager(store: f.store, home: f.home.standardizedFileURL, permittedRoot: f.session)
            XCTAssertTrue(try XCTUnwrap(manager.pending().first).canRestoreSource)
            try manager.restoreSource(id: f.journal.id)
            XCTAssertEqual(try FileTree.digest(f.source), try FileTree.digest(f.copy))
            XCTAssertEqual(f.store.operations().first?.phase, .resolved)
        }
    }
    func testLegacyRecoveryAcceptsAbsentPhysicalSourceWithinStandardizedHome() throws {
        let f = try fixture(parent: FileManager.default.temporaryDirectory)
        try RecoveryManager(store: f.store, home: f.home.standardizedFileURL).restoreSource(id: f.journal.id)
        XCTAssertEqual(try FileTree.digest(f.source), try FileTree.digest(f.copy))
        XCTAssertEqual(f.store.operations().first?.phase, .resolved)
    }
    func testScopedRestoreRecoveryCompletesGeneratedCacheConfiguration() throws {
        let f = try fixture(), tool = try XCTUnwrap(CacheCatalog.find("npm", home: f.home))
        let disk = f.session.appendingPathComponent("generated-ssd"), fm = FileManager.default
        try fm.createDirectory(at: disk, withIntermediateDirectories: true)
        try fm.createDirectory(at: tool.source, withIntermediateDirectories: true)
        try Data("generated cache".utf8).write(to: tool.source.appendingPathComponent("artifact"))
        let expected = try FileTree.digest(tool.source)
        let volume = VolumeInfo(uuid: "GENERATED-SCOPE-VOLUME", name: "Fixture", path: disk.path, totalBytes: 1_000_000_000_000, freeBytes: 900_000_000_000, isInternal: false, isWritable: true)
        var settings = AppSettings(); settings.selectedVolumeUUID = volume.uuid; try f.store.save(settings)
        _ = try MigrationEngine(store: f.store, home: f.home, volumeProvider: { _ in volume }, verifyNative: false).migrate(toolID: "npm", removeLocal: true)
        let location = try XCTUnwrap(f.store.settings().locations["npm"]), external = tool.payload(at: disk.appendingPathComponent(location.relativePath))
        let engine = MigrationEngine(store: f.store, home: f.home, volumeProvider: { _ in volume }, verifyNative: false, checkpoint: { journal in
            if journal.kind == "restore" && journal.phase == .copyVerified { throw CacheSSDError.message("Generated interruption") }
        })
        XCTAssertThrowsError(try engine.restore(toolID: "npm"))
        let record = try XCTUnwrap(f.store.operations().first(where: { $0.kind == "restore" })), manager = f.manager()
        XCTAssertTrue(try XCTUnwrap(manager.pending().first(where: { $0.id == record.id })).canRestoreSource)
        try manager.restoreSource(id: record.id)
        XCTAssertNil(f.store.settings().locations["npm"])
        XCTAssertEqual(try FileTree.digest(tool.source), expected)
        XCTAssertEqual(try FileTree.digest(external), expected)
    }
    func testEveryRecordedPathRejectsOutsideOrRedirectedLocations() throws {
        for key in ["source", "destination", "staging", "quarantine", "trashPath"] {
            let f = try fixture()
            let path = f.store.base.appendingPathComponent(f.name)
            var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
            value[key] = f.sibling.path
            try JSONSerialization.data(withJSONObject: value).write(to: path)
            let manager = f.manager()
            XCTAssertFalse(try XCTUnwrap(manager.pending().first).canRestoreSource, key)
            XCTAssertThrowsError(try manager.restoreSource(id: f.journal.id), key)
            XCTAssertThrowsError(try manager.keepCopiesAndResolve(id: f.journal.id), key)
        }
        var f = try fixture()
        let link = f.session.appendingPathComponent("redirected")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.root)
        f.journal.destination = link.appendingPathComponent("absent.txt").path
        try f.store.writeDurably(f.journal, name: f.name)
        XCTAssertFalse(try XCTUnwrap(f.manager().pending().first).canRestoreSource)
        XCTAssertThrowsError(try f.manager().restoreSource(id: f.journal.id))
    }
    func testRedirectedAndFIFOOperationRecordsAreNotReadOrRewritten() throws {
        for fifo in [false, true] {
            let f = try fixture(), manager = f.manager(), path = f.store.base.appendingPathComponent(f.name)
            let original = try Data(contentsOf: path)
            try original.write(to: f.sibling)
            try FileManager.default.removeItem(at: path)
            if fifo { XCTAssertEqual(mkfifo(path.path, 0o600), 0) }
            else { try FileManager.default.createSymbolicLink(at: path, withDestinationURL: f.sibling) }
            XCTAssertTrue(manager.pending().isEmpty)
            XCTAssertThrowsError(try manager.restoreSource(id: f.journal.id))
            XCTAssertEqual(try Data(contentsOf: f.sibling), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.path))
        }
    }
    func testRedirectedStoreIsRejectedBeforeCreatingALeaseOutsideSession() throws {
        let f = try fixture(), manager = f.manager(), fm = FileManager.default
        let outside = f.root.appendingPathComponent("outside-store")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.moveItem(at: f.store.base, to: f.session.appendingPathComponent("saved-support"))
        try fm.createSymbolicLink(at: f.store.base, withDestinationURL: outside)
        XCTAssertTrue(manager.pending().isEmpty)
        XCTAssertThrowsError(try manager.restoreSource(id: f.journal.id))
        XCTAssertThrowsError(try manager.keepCopiesAndResolve(id: f.journal.id))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
    func testReplacedSessionIdentityCannotEnableOldRecoveryManager() throws {
        let f = try fixture(), manager = f.manager(), fm = FileManager.default
        let moved = f.root.appendingPathComponent("retained-session")
        try fm.moveItem(at: f.session, to: moved)
        try fm.createDirectory(at: f.session, withIntermediateDirectories: true)
        XCTAssertTrue(manager.pending().isEmpty)
        XCTAssertThrowsError(try manager.restoreSource(id: f.journal.id))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: f.session.path).isEmpty)
    }
}
