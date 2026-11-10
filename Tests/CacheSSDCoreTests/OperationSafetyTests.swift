import XCTest
import Foundation
import Darwin
@testable import CacheSSDCore

final class OperationSafetyTests: XCTestCase {
    var root: URL!
    var home: URL!
    var store: Store!
    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = parent.appendingPathComponent("DiskWing-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = Paths.physicalURL(root)
        home = root.appendingPathComponent("home"); store = Store(base: root.appendingPathComponent("support"))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func file(_ path: String, content: String = "original bytes") throws -> URL {
        let item = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: item.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: item)
        return item
    }
    func personalSource() throws -> URL { try file("home/Downloads/example.txt") }
    func target() throws -> URL {
        let path = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true); return path
    }
    func fakeTrash(_ source: URL) throws -> URL? {
        let destination = root.appendingPathComponent("trash/\(UUID().uuidString)/\(source.lastPathComponent)")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: destination); return destination
    }
    func migrationFixture() throws -> (CacheDescriptor, VolumeInfo) {
        let tool = CacheCatalog.find("npm", home: home)!
        try FileManager.default.createDirectory(at: tool.source, withIntermediateDirectories: true)
        try Data("cached bytes".utf8).write(to: tool.source.appendingPathComponent("artifact"))
        let disk = root.appendingPathComponent("SSD"); try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
        let volume = VolumeInfo(uuid: "SAMPLE-UUID", name: "Sample", path: disk.path, totalBytes: 1_000_000_000_000, freeBytes: 900_000_000_000, isInternal: false, isWritable: true)
        var settings = AppSettings(); settings.selectedVolumeUUID = volume.uuid; try store.save(settings)
        return (tool, volume)
    }
    func testUnreadableShellFileIsNeverReplacedOrBackedUpAsEmpty() throws {
        let rc = try file("home/.zshrc", content: "precious configuration\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: rc.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rc.path) }
        XCTAssertThrowsError(try ShellIntegration.install(helper: URL(fileURLWithPath: "/usr/bin/true"), store: store, home: home))
        XCTAssertThrowsError(try ShellIntegration.uninstall(store: store, home: home))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.base.appendingPathComponent("integration.zsh").path))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rc.path)
        XCTAssertEqual(try String(contentsOf: rc), "precious configuration\n")
    }
    func testInvalidEncodingIsNotTreatedAsEmptyConfiguration() throws {
        let rc = try file("home/.zshrc"); let bytes = Data([0xff, 0xfe, 0x80])
        try bytes.write(to: rc)
        XCTAssertThrowsError(try ShellIntegration.install(helper: URL(fileURLWithPath: "/usr/bin/true"), store: store, home: home))
        XCTAssertEqual(try Data(contentsOf: rc), bytes)
    }
    func testMeasurementDistinguishesMissingEmptyAndUnreadable() throws {
        XCTAssertTrue(FileTree.measure(root.appendingPathComponent("absent")).missing)
        let empty = root.appendingPathComponent("empty"); try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertTrue(FileTree.measure(empty).isComplete)
        let blocked = try file("blocked/file").deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path) }
        let reading = FileTree.measure(blocked)
        XCTAssertFalse(reading.isComplete); XCTAssertFalse(reading.unreadablePaths.isEmpty)
    }
    func testOneLeaseBlocksAllMutationEntryPoints() throws {
        let source = try personalSource(), destination = try target()
        let lease = try OperationLease(store: store)
        defer { withExtendedLifetime(lease) {} }
        XCTAssertThrowsError(try PersonalActions(home: home, store: store).move(source, to: destination))
        XCTAssertThrowsError(try PersonalActions(home: home, store: store).trash(source))
        XCTAssertThrowsError(try MigrationEngine(store: store, home: home).restore(toolID: "npm"))
        XCTAssertThrowsError(try ShellIntegration.install(helper: URL(fileURLWithPath: "/usr/bin/true"), store: store, home: home))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertThrowsError(try XcodeIntegration.useLocalDerivedData(store: store))
    }
    func testMovePreservesBytesMetadataAndTrashRecovery() throws {
        let source = try personalSource(), destination = try target()
        try FileManager.default.setAttributes([.posixPermissions: 0o640, .modificationDate: Date(timeIntervalSince1970: 1_500_000_000)], ofItemAtPath: source.path)
        let bytes = Data("resource fork".utf8)
        XCTAssertEqual(bytes.withUnsafeBytes { setxattr(source.path, "com.apple.ResourceFork", $0.baseAddress, bytes.count, 0, 0) }, 0)
        let expected = try FileTree.digest(source)
        _ = try PersonalActions(home: home, store: store, trashHandler: fakeTrash, busyCheck: { _, _ in [] }).move(source, to: destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try FileTree.digest(destination.appendingPathComponent(source.lastPathComponent)), expected)
        let operation = try XCTUnwrap(store.operations().first)
        XCTAssertEqual(operation.phase, .completed)
        XCTAssertEqual(try FileTree.digest(URL(fileURLWithPath: XCTUnwrap(operation.trashPath))), expected)
    }
    func testFullDestinationPreservesSourceWithoutStaging() throws {
        let source = try personalSource(), destination = try target()
        XCTAssertThrowsError(try PersonalActions(home: home, store: store, freeBytes: { _ in 0 }, trashHandler: fakeTrash, busyCheck: { _, _ in [] }).move(source, to: destination))
        XCTAssertEqual(try String(contentsOf: source), "original bytes")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }
    func testFolderContainingProtectedProjectIsNotMoved() throws {
        _ = try file("home/Documents/project/.git/config")
        let source = home.appendingPathComponent("Documents/project")
        XCTAssertThrowsError(try PersonalActions(home: home, store: store, trashHandler: fakeTrash).move(source, to: target()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testCancellationAfterVerificationKeepsOriginalAndPendingRecord() throws {
        let source = try personalSource(), destination = try target(), token = CancellationFlag()
        var reachedCheckpoint = false
        let actions = PersonalActions(home: home, store: store, trashHandler: fakeTrash, busyCheck: { _, _ in [] }, checkpoint: { if $0.phase == .copyVerified { reachedCheckpoint = true; token.cancel() } })
        XCTAssertThrowsError(try actions.move(source, to: destination, cancellation: token))
        XCTAssertTrue(reachedCheckpoint)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(store.operations().first?.phase, .cancelled)
        XCTAssertEqual(RecoveryManager(store: store, home: home).pending().count, 1)
    }
    func testFailureAfterPublicationKeepsBothAndCanBeResolvedWithoutDeleting() throws {
        let source = try personalSource(), destination = try target()
        var reachedCheckpoint = false
        let actions = PersonalActions(home: home, store: store, trashHandler: fakeTrash, busyCheck: { _, _ in [] }, checkpoint: {
            if $0.phase == .published { reachedCheckpoint = true; throw CacheSSDError.message("injected stop") }
        })
        XCTAssertThrowsError(try actions.move(source, to: destination))
        XCTAssertTrue(reachedCheckpoint, "The intended published boundary must be reached before injected failure")
        let record = try XCTUnwrap(store.operations().first)
        XCTAssertEqual(record.phase, .interrupted)
        XCTAssertTrue(record.detail.contains("injected stop"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent(source.lastPathComponent).path))
        try RecoveryManager(store: store, home: home).keepCopiesAndResolve(id: record.id)
        XCTAssertTrue(RecoveryManager(store: store, home: home).pending().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testRecoveryRestoresAbsentSourceAndNeverOverwrites() throws {
        let source = try personalSource(), destination = try target()
        var reachedCheckpoint = false
        let actions = PersonalActions(home: home, store: store, trashHandler: fakeTrash, busyCheck: { _, _ in [] }, checkpoint: {
            if $0.phase == .completed { reachedCheckpoint = true; throw CacheSSDError.message("simulated completion failure") }
        })
        XCTAssertThrowsError(try actions.move(source, to: destination))
        XCTAssertTrue(reachedCheckpoint)
        let record = try XCTUnwrap(store.operations().first)
        let recovery = RecoveryManager(store: store, home: home, busyCheck: { _, _ in [] })
        try recovery.restoreSource(id: record.id)
        XCTAssertEqual(try String(contentsOf: source), "original bytes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent(source.lastPathComponent).path))
        XCTAssertThrowsError(try recovery.restoreSource(id: record.id))
    }
    func testVerifiedMigrationCanBeRestoredWithoutOverwritingLocalCache() throws {
        let (tool, volume) = try migrationFixture()
        let engine = MigrationEngine(store: store, home: home, volumeProvider: { _ in volume }, verifyNative: false, busyCheck: { _, _ in [] })
        _ = try engine.migrate(toolID: "npm", removeLocal: true)
        try engine.restore(toolID: "npm")
        XCTAssertEqual(try String(contentsOf: tool.source.appendingPathComponent("artifact")), "cached bytes")
        XCTAssertNil(store.settings().locations["npm"])
        XCTAssertEqual(store.operations().filter { $0.phase == .completed }.count, 2)
    }
    func testRestoreDetectsConcurrentLocalUseAndPreservesBothCopies() throws {
        let (tool, volume) = try migrationFixture()
        let engine = MigrationEngine(store: store, home: home, volumeProvider: { _ in volume }, verifyNative: false, busyCheck: { _, _ in [] })
        _ = try engine.migrate(toolID: "npm", removeLocal: true)
        let other = MigrationEngine(store: store, home: home, volumeProvider: { _ in volume }, verifyNative: false, busyCheck: { _, _ in [] }, checkpoint: {
            if $0.kind == "restore" && $0.phase == .copyVerified { try Data("new local data".utf8).write(to: tool.source.appendingPathComponent("new")) }
        })
        XCTAssertThrowsError(try other.restore(toolID: "npm"))
        XCTAssertEqual(try String(contentsOf: tool.source.appendingPathComponent("new")), "new local data")
        XCTAssertNotNil(store.settings().locations["npm"])
    }

    func testMoveBecomingBusyAfterVerificationPreservesSourceAndVerifiedStaging() throws {
        let source = try personalSource(), destination = try target(), expected = try FileTree.digest(source)
        var busy = false, inspected = 0, trashed = false, phases: [OperationPhase] = []
        let actions = PersonalActions(home: home, store: store, trashHandler: { item in
            trashed = true; return try self.fakeTrash(item)
        }, busyCheck: { paths, tool in
            XCTAssertEqual(paths.map(\.path), [source.path]); XCTAssertNil(tool); inspected += 1
            return busy ? [BusyProcess(pid: 4242, name: "Controlled fixture holder")] : []
        }, checkpoint: { journal in
            phases.append(journal.phase)
            if journal.phase == .copyVerified { busy = true }
        })
        XCTAssertThrowsError(try actions.move(source, to: destination))
        XCTAssertTrue(phases.contains(.copyVerified)); XCTAssertFalse(phases.contains(.published))
        XCTAssertFalse(trashed); XCTAssertEqual(inspected, 2)
        XCTAssertEqual(try FileTree.digest(source), expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent(source.lastPathComponent).path))
        let journal = try XCTUnwrap(store.operations().first)
        XCTAssertEqual(journal.phase, .interrupted)
        XCTAssertEqual(try FileTree.digest(URL(fileURLWithPath: XCTUnwrap(journal.staging))), expected)
    }

    func testMoveBecomingBusyAfterPublicationOrAtTrashKeepsBothCopies() throws {
        for phase in [OperationPhase.published, .trashing] {
            let source = try file("home/Downloads/reopened-\(phase.rawValue).txt"), destination = try target()
            let expected = try FileTree.digest(source)
            var busy = false, reachedCheckpoint = false, trashed = false, inspections = 0
            let actions = PersonalActions(home: home, store: store, trashHandler: { item in
                trashed = true; return try self.fakeTrash(item)
            }, busyCheck: { paths, tool in
                XCTAssertEqual(paths.map(\.path), [source.path]); XCTAssertNil(tool)
                inspections += 1
                return busy ? [BusyProcess(pid: 4242, name: "Controlled late fixture holder")] : []
            }, checkpoint: { journal in
                if journal.phase == phase { reachedCheckpoint = true; busy = true }
            })
            XCTAssertThrowsError(try actions.move(source, to: destination), phase.rawValue)
            XCTAssertTrue(reachedCheckpoint, phase.rawValue); XCTAssertFalse(trashed, phase.rawValue)
            XCTAssertEqual(inspections, 3, phase.rawValue)
            let sourceExists = FileManager.default.fileExists(atPath: source.path)
            XCTAssertTrue(sourceExists, phase.rawValue)
            if sourceExists { XCTAssertEqual(try FileTree.digest(source), expected, phase.rawValue) }
            XCTAssertEqual(try FileTree.digest(destination.appendingPathComponent(source.lastPathComponent)), expected, phase.rawValue)
            let journal = try XCTUnwrap(store.operations().first(where: { $0.source == source.path }))
            XCTAssertEqual(journal.phase, .interrupted, phase.rawValue)
        }
    }

    private func verifyChangeDuringFinalBusyCheck(moving: Bool, cancelling: Bool) throws {
        let child = try file("home/Downloads/final-busy-\(UUID().uuidString)/child.txt")
        let source = child.deletingLastPathComponent(), destination = try target(), token = CancellationFlag()
        let expected = try FileTree.digest(source), directoryIdentity = try FileIdentity(source)
        let finalInspection = moving ? 3 : 2
        var inspected = 0, reachedTrashCheckpoint = false, published = false, trashed = false
        let actions = PersonalActions(home: home, store: store, trashHandler: { item in
            trashed = true; return try self.fakeTrash(item)
        }, busyCheck: { paths, tool in
            XCTAssertEqual(paths.map(\.path), [source.path]); XCTAssertNil(tool)
            inspected += 1
            if inspected == finalInspection {
                XCTAssertTrue(reachedTrashCheckpoint)
                if moving { XCTAssertTrue(published) }
                if cancelling { token.cancel() }
                else {
                    try Data("updated child while inspecting processes".utf8).write(to: child)
                    XCTAssertEqual(try FileIdentity(source), directoryIdentity, "Changing a child must leave the folder identity unchanged")
                }
            }
            return []
        }, checkpoint: { journal in
            if journal.phase == .trashing { reachedTrashCheckpoint = true }
            if journal.phase == .published { published = true }
        })
        if moving { XCTAssertThrowsError(try actions.move(source, to: destination, cancellation: token)) }
        else { XCTAssertThrowsError(try actions.trash(source, cancellation: token)) }
        XCTAssertEqual(inspected, finalInspection); XCTAssertTrue(reachedTrashCheckpoint); XCTAssertFalse(trashed)
        let sourceExists = FileManager.default.fileExists(atPath: source.path)
        XCTAssertTrue(sourceExists)
        if sourceExists {
            XCTAssertEqual(try String(contentsOf: child), cancelling ? "original bytes" : "updated child while inspecting processes")
        }
        if moving { XCTAssertEqual(try FileTree.digest(destination.appendingPathComponent(source.lastPathComponent)), expected) }
        let journal = try XCTUnwrap(store.operations().first(where: { $0.source == source.path }))
        XCTAssertEqual(journal.phase, cancelling ? .cancelled : .interrupted)
    }
    func testMoveCancellationDuringFinalBusyInspectionKeepsBothCopies() throws {
        try verifyChangeDuringFinalBusyCheck(moving: true, cancelling: true)
    }
    func testTrashCancellationDuringFinalBusyInspectionPreservesSource() throws {
        try verifyChangeDuringFinalBusyCheck(moving: false, cancelling: true)
    }
    func testMoveChildMutationDuringFinalBusyInspectionKeepsBothCopies() throws {
        try verifyChangeDuringFinalBusyCheck(moving: true, cancelling: false)
    }
    func testTrashChildMutationDuringFinalBusyInspectionPreservesSource() throws {
        try verifyChangeDuringFinalBusyCheck(moving: false, cancelling: false)
    }

    private enum InspectionFailure: Error { case unavailable }
    func testBusyInspectionErrorsPropagateWithoutChangingPersonalOrCacheSources() throws {
        let source = try personalSource(), destination = try target(), expected = try FileTree.digest(source)
        let actions = PersonalActions(home: home, store: store, trashHandler: fakeTrash, busyCheck: { paths, tool in
            XCTAssertEqual(paths.map(\.path), [source.path]); XCTAssertNil(tool); throw InspectionFailure.unavailable
        })
        XCTAssertThrowsError(try actions.move(source, to: destination)) { XCTAssertTrue($0 is InspectionFailure) }
        XCTAssertThrowsError(try actions.trash(source)) { XCTAssertTrue($0 is InspectionFailure) }
        XCTAssertEqual(try FileTree.digest(source), expected)
        XCTAssertTrue(store.operations().isEmpty)
        let (tool, volume) = try migrationFixture(), cacheExpected = try FileTree.digest(tool.source)
        let engine = MigrationEngine(store: store, home: home, volumeProvider: { _ in volume }, verifyNative: false, busyCheck: { paths, toolID in
            XCTAssertEqual(paths.map(\.path), [tool.source.path]); XCTAssertEqual(toolID, tool.id); throw InspectionFailure.unavailable
        })
        XCTAssertThrowsError(try engine.migrate(toolID: tool.id, removeLocal: true)) { XCTAssertTrue($0 is InspectionFailure) }
        XCTAssertEqual(try FileTree.digest(tool.source), cacheExpected)
        XCTAssertTrue(store.operations().isEmpty)
    }

    func testRecoveryBusyInspectionErrorPreservesCopyAndPendingJournal() throws {
        let source = try personalSource(), copy = try target().appendingPathComponent(source.lastPathComponent)
        try FileTree.copyItem(source, to: copy)
        let expected = try FileTree.digest(source)
        var journal = try OperationJournal(kind: "personalMove", source: source, destination: copy)
        journal.sourceDigest = expected; journal.destinationDigest = expected; journal.phase = .interrupted
        let name = "operation-\(journal.id.uuidString).json"
        try store.writeDurably(journal, name: name); try FileManager.default.removeItem(at: source)
        let before = try Data(contentsOf: store.base.appendingPathComponent(name))
        let recovery = RecoveryManager(store: store, home: home, busyCheck: { paths, tool in
            XCTAssertEqual(paths.map(\.path), [copy.path]); XCTAssertNil(tool); throw InspectionFailure.unavailable
        })
        XCTAssertThrowsError(try recovery.restoreSource(id: journal.id)) { XCTAssertTrue($0 is InspectionFailure) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try FileTree.digest(copy), expected)
        XCTAssertEqual(try Data(contentsOf: store.base.appendingPathComponent(name)), before)
    }

    func testChangedScanIdentityPreventsTrashAndMove() throws {
        let source = try personalSource(), destination = try target(), scanned = try FileIdentity(source)
        try Data("updated content after scanning".utf8).write(to: source)
        let actions = PersonalActions(home: home, store: store, trashHandler: fakeTrash)
        XCTAssertThrowsError(try actions.trash(source, expectedIdentity: scanned))
        XCTAssertThrowsError(try actions.move(source, to: destination, expectedIdentity: scanned))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(store.operations().isEmpty)
    }
    func testBunAbsoluteInternalLinksBecomePortableAndExternalLinksStayBlocked() throws {
        let source = root.appendingPathComponent("bun-cache"), copy = root.appendingPathComponent("bun-copy")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let payload = source.appendingPathComponent("package"); try Data("package".utf8).write(to: payload)
        let link = source.appendingPathComponent("version")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: payload)
        let original = try FileTree.manifest(source, tool: "bun")
        try FileTree.copy(source, to: copy, tool: "bun")
        XCTAssertEqual(try FileTree.manifest(copy, tool: "bun"), original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: copy.appendingPathComponent("version").path), "package")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("outside"))
        XCTAssertThrowsError(try FileTree.manifest(source, tool: "bun"))
    }
    func testRetentionNeverDropsPendingOrUnreadableRecords() throws {
        let source = try personalSource()
        for _ in 0..<4 {
            var journal = try OperationJournal(kind: "trash", source: source)
            journal.phase = .completed
            try store.writeDurably(journal, name: "operation-\(journal.id).json")
        }
        let pending = try OperationJournal(kind: "trash", source: source)
        try store.writeDurably(pending, name: "operation-\(pending.id).json")
        let invalid = store.base.appendingPathComponent("operation-invalid.json")
        try Data("corrupted".utf8).write(to: invalid)
        try store.pruneCompletedOperations(keeping: 2)
        XCTAssertEqual(store.operations().count,3)
        XCTAssertEqual(store.unreadableOperationRecords(), ["operation-invalid.json"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: invalid.path))
    }
}
