import XCTest
import Foundation
import Darwin
@testable import CacheSSDCore

final class VolumeTrashTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var disk: URL!
    private var store: Store!
    private var volume: VolumeInfo!
    private var available = true
    private var trashCalls = 0

    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-volume-trash-\(UUID().uuidString)")
        home = root.appendingPathComponent("home"); disk = root.appendingPathComponent("External")
        for path in [home!, disk!] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
        store = Store(base: root.appendingPathComponent("support"))
        volume = descriptor(disk); available = true; trashCalls = 0
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func descriptor(_ url: URL, uuid: String = "GENERATED-VOLUME", writable: Bool = true, free: Int64 = 10_000_000_000) -> VolumeInfo {
        VolumeInfo(uuid: uuid, name: "Generated volume", path: url.path, totalBytes: 20_000_000_000, freeBytes: free, isInternal: false, isWritable: writable)
    }
    private func provider(_ uuid: String) -> VolumeInfo? { available && volume.uuid == uuid ? volume : nil }
    private func put(_ relative: String, bytes: String = "generated personal content") throws -> URL {
        let item = disk.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: item.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes.utf8).write(to: item); return item
    }
    private func fakeTrash(_ source: URL) throws -> URL? {
        trashCalls += 1
        let target = URL(fileURLWithPath: volume.path).appendingPathComponent(".Trashes/generated/\(UUID().uuidString)/\(source.lastPathComponent)")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: target); return target
    }
    private func actions(protected: [URL] = [], capability: @escaping (VolumeInfo) -> Bool = { _ in true },
                         busy: @escaping BusyCheck = { _, _ in [] }, checkpoint: @escaping (OperationJournal) throws -> Void = { _ in }) -> PersonalActions {
        PersonalActions(home: home, store: store, trashHandler: fakeTrash, busyCheck: busy, checkpoint: checkpoint,
                        volumeProvider: provider, protectedRoots: protected, finderTrashAvailable: capability)
    }
    private func recovery(protected: [URL] = [], busy: @escaping BusyCheck = { _, _ in [] }, checkpoint: @escaping (OperationJournal) throws -> Void = { _ in }) -> RecoveryManager {
        RecoveryManager(store: store, home: home, busyCheck: busy, checkpoint: checkpoint, volumeProvider: provider, protectedRoots: protected, finderTrashAvailable: { _ in true })
    }
    private func interrupted() throws -> (URL, OperationJournal, String) {
        let source = try put("personal/generated/file.txt").deletingLastPathComponent()
        let digest = try FileTree.digest(source), scope = try VolumeTrashScope(item: source, volume: volume)
        var operationID: UUID?
        let action = actions(checkpoint: { record in
            if record.phase == .published { operationID = record.id; throw CacheSSDError.message("Generated interruption") }
        })
        XCTAssertThrowsError(try action.trash(source, scope: scope))
        let record = try XCTUnwrap(store.operations().first { $0.id == operationID })
        XCTAssertEqual(record.phase, .interrupted); XCTAssertEqual(record.sourceDigest, digest)
        return (source, record, digest)
    }

    func testReviewedExternalPersonalFileUsesVolumeBoundTrashJournal() throws {
        let item = try put("documents/notes.txt"), identity = try FileIdentity(item)
        let scope = try VolumeTrashScope(item: item, volume: volume, expectedIdentity: identity)
        XCTAssertNil(PersonalActionPolicy.reasonPreventingTrash(item, on: volume, home: home, storeBase: store.base))
        XCTAssertNotNil(PersonalActionPolicy.reasonPreventingTrash(item, home: home))
        XCTAssertNotNil(PersonalActionPolicy.reasonPreventing(item, home: home))
        let record = try actions().trash(item, expectedIdentity: identity, scope: scope)
        XCTAssertNil(record.measuredFreeDelta); XCTAssertEqual(trashCalls, 1)
        let journal = try XCTUnwrap(store.operations().first)
        XCTAssertEqual(journal.kind, "volumeTrash"); XCTAssertEqual(journal.schemaVersion, 1)
        XCTAssertEqual(journal.volumeTrashScope?.volumeUUID, volume.uuid)
        XCTAssertEqual(journal.volumeTrashScope?.relativePath, "documents/notes.txt")
        XCTAssertEqual(journal.trashIdentity?.inode, identity.inode)
        XCTAssertTrue(journal.trashRelativePath?.hasPrefix(".Trashes/") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.path))
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: XCTUnwrap(journal.trashPath))), "generated personal content")
    }
    func testOutsideHomeStillRequiresExplicitReviewedScope() throws {
        let item = try put("personal.txt")
        XCTAssertThrowsError(try actions().trash(item))
        XCTAssertEqual(trashCalls, 0); XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
    }
    func testScopeRejectsVolumeRootOtherVolumeAndChangedScannedIdentity() throws {
        XCTAssertThrowsError(try VolumeTrashScope(item: disk, volume: volume))
        let outside = root.appendingPathComponent("outside.txt"); try Data().write(to: outside)
        XCTAssertThrowsError(try VolumeTrashScope(item: outside, volume: volume))
        let item = try put("personal.txt"), identity = try FileIdentity(item)
        try Data("changed since scan".utf8).write(to: item)
        XCTAssertThrowsError(try VolumeTrashScope(item: item, volume: volume, expectedIdentity: identity))
    }
    func testDifferentReviewedArgumentCannotUseAnotherItemScope() throws {
        let first = try put("first.txt"), second = try put("second.txt")
        let scope = try VolumeTrashScope(item: first, volume: volume)
        XCTAssertThrowsError(try actions().trash(second, scope: scope))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path)); XCTAssertEqual(trashCalls, 0)
    }
    func testMissingReadOnlyOrReplacedMountPreservesSelection() throws {
        let item = try put("personal.txt"), scope = try VolumeTrashScope(item: item, volume: volume)
        available = false; XCTAssertThrowsError(try actions().trash(item, scope: scope)); available = true
        volume = descriptor(disk, writable: false); XCTAssertThrowsError(try actions().trash(item, scope: scope))
        volume = descriptor(disk)
        let retained = root.appendingPathComponent("RetainedVolume")
        try FileManager.default.moveItem(at: disk, to: retained)
        try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: false)
        _ = try put("personal.txt", bytes: "replacement volume item")
        XCTAssertThrowsError(try actions().trash(item, scope: scope))
        XCTAssertEqual(try String(contentsOf: retained.appendingPathComponent("personal.txt")), "generated personal content")
        XCTAssertEqual(try String(contentsOf: item), "replacement volume item"); XCTAssertEqual(trashCalls, 0)
    }
    func testRenameBeforeConfirmationResolvesUUIDAndPreservesSelectedIdentity() throws {
        let item = try put("personal.txt"), scope = try VolumeTrashScope(item: item, volume: volume)
        let renamed = root.appendingPathComponent("RenamedVolume")
        try FileManager.default.moveItem(at: disk, to: renamed); volume = descriptor(renamed)
        _ = try actions().trash(item, scope: scope)
        XCTAssertEqual(trashCalls, 1)
        let journal = try XCTUnwrap(store.operations().first)
        XCTAssertEqual(journal.source, renamed.appendingPathComponent("personal.txt").path)
        XCTAssertEqual(journal.volumeTrashScope?.reviewedPath, item.path)
    }
    func testRootsSensitiveProfilesAndInstalledDataRemainProtectedOnExternalVolume() throws {
        for relative in ["System/generated", "Library/Caches/generated", "backup/.ssh/key", "backup/.aws/credentials", "backup/.env", "backup/Library/Application Support/Google/Chrome/Default/History", "backup/Library/Developer/CoreSimulator/generated", "backup/Library/Android/sdk/adb", "backup/.bun/install/cache/pkg", "backup/.cache/uv/pkg", "backup/.npm/_npx/pkg", "backup/Generated.app/Contents/data", "MacCaches/CacheSSD/id/cache"] {
            let source = try put(relative), scope = try VolumeTrashScope(item: source, volume: volume)
            XCTAssertNotNil(PersonalActionPolicy.reasonPreventingTrash(source, on: volume, home: home, storeBase: store.base), relative)
            XCTAssertThrowsError(try actions().trash(source, scope: scope), relative)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        }
        XCTAssertEqual(trashCalls, 0)
    }
    func testSuppliedManagedRootsAndTheirAncestorsCannotBeTrashed() throws {
        let item = try put("managed/generations/active/data"), managed = disk.appendingPathComponent("managed/generations")
        for selection in [item, managed, managed.deletingLastPathComponent()] {
            let scope = try VolumeTrashScope(item: selection, volume: volume)
            XCTAssertThrowsError(try actions(protected: [managed]).trash(selection, scope: scope))
        }
        XCTAssertEqual(trashCalls, 0)
    }
    func testDirectoryTreeContainingSensitiveChildOrLinkIsPreserved() throws {
        let source = try put("personal/tree/nested/.env").deletingLastPathComponent().deletingLastPathComponent()
        let scope = try VolumeTrashScope(item: source, volume: volume)
        XCTAssertThrowsError(try actions().trash(source, scope: scope))
        try FileManager.default.removeItem(at: source.appendingPathComponent("nested/.env"))
        let outside = root.appendingPathComponent("outside.txt"); try Data("outside protected".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: outside)
        let linked = try VolumeTrashScope(item: source, volume: volume)
        XCTAssertThrowsError(try actions().trash(source, scope: linked))
        XCTAssertEqual(try String(contentsOf: outside), "outside protected"); XCTAssertEqual(trashCalls, 0)
    }
    func testScopeRejectsLeafAndAncestorSymlinks() throws {
        let actual = try put("actual/data").deletingLastPathComponent(), link = disk.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)
        XCTAssertThrowsError(try VolumeTrashScope(item: link, volume: volume))
        XCTAssertThrowsError(try VolumeTrashScope(item: link.appendingPathComponent("data"), volume: volume))
    }
    func testUnsupportedTrashCapabilityFailsBeforeMutation() throws {
        let item = try put("personal.txt"), scope = try VolumeTrashScope(item: item, volume: volume)
        XCTAssertThrowsError(try actions(capability: { _ in false }).trash(item, scope: scope))
        XCTAssertEqual(trashCalls, 0); XCTAssertTrue(store.operations().isEmpty)
    }
    func testVolumeLossOrSourceMutationAtFinalBoundaryDoesNotTrash() throws {
        let item = try put("personal.txt"), scope = try VolumeTrashScope(item: item, volume: volume)
        let action = actions(checkpoint: { record in if record.phase == .trashing { self.available = false } })
        XCTAssertThrowsError(try action.trash(item, scope: scope)); available = true
        XCTAssertEqual(trashCalls, 0); XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
        let second = actions(checkpoint: { record in if record.phase == .trashing { try Data("new bytes".utf8).write(to: item) } })
        XCTAssertThrowsError(try second.trash(item, scope: scope)); XCTAssertEqual(trashCalls, 0)
        XCTAssertEqual(try String(contentsOf: item), "new bytes")
    }
    func testRecoveryRenamesFromSameVolumeTrashEvenWithNoReportedFreeSpace() throws {
        let (source, journal, before) = try interrupted()
        let trash = URL(fileURLWithPath: try XCTUnwrap(journal.trashPath)), identity = try FileIdentity(trash)
        volume = descriptor(disk, free: 0)
        XCTAssertTrue(try XCTUnwrap(recovery().pending().first { $0.id == journal.id }).canRestoreSource)
        try recovery().restoreSource(id: journal.id)
        XCTAssertEqual(try FileTree.digest(source), before)
        XCTAssertEqual(try FileIdentity(source).inode, identity.inode)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trash.path))
        XCTAssertEqual(store.operations().first { $0.id == journal.id }?.phase, .resolved)
    }
    func testRecoveryUsesRelativePathsAfterVolumeRename() throws {
        let (_, journal, before) = try interrupted()
        let renamed = root.appendingPathComponent("RenamedVolume")
        try FileManager.default.moveItem(at: disk, to: renamed); volume = descriptor(renamed)
        try recovery().restoreSource(id: journal.id)
        XCTAssertEqual(try FileTree.digest(renamed.appendingPathComponent("personal/generated")), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.source))
    }
    func testRecreatedDestinationAndRedirectedParentPreserveTrash() throws {
        let (source, journal, _) = try interrupted(), trash = URL(fileURLWithPath: try XCTUnwrap(journal.trashPath))
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("recreated".utf8).write(to: source.appendingPathComponent("new"))
        XCTAssertThrowsError(try recovery().restoreSource(id: journal.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
        try FileManager.default.removeItem(at: source)
        let parent = source.deletingLastPathComponent(), retained = disk.appendingPathComponent("retained-parent")
        try FileManager.default.moveItem(at: parent, to: retained)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: retained)
        XCTAssertThrowsError(try recovery().restoreSource(id: journal.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }
    func testRecoveryRechecksBeforePublishingWithoutOverwrite() throws {
        let (source, journal, _) = try interrupted(), trash = URL(fileURLWithPath: try XCTUnwrap(journal.trashPath))
        let action = recovery(checkpoint: { record in
            if record.phase == .publishing {
                try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
                try Data("new protected bytes".utf8).write(to: source.appendingPathComponent("new"))
            }
        })
        XCTAssertThrowsError(try action.restoreSource(id: journal.id))
        XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("new")), "new protected bytes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
    }
    func testFutureNestedScopeVersionIsPreservedWithoutRewrite() throws {
        let (_, journal, _) = try interrupted()
        let file = store.base.appendingPathComponent("operation-\(journal.id.uuidString).json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var scope = try XCTUnwrap(object["volumeTrashScope"] as? [String: Any]); scope["schemaVersion"] = 99; scope["futureProof"] = "preserve"
        object["volumeTrashScope"] = scope
        let bytes = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys); try bytes.write(to: file)
        XCTAssertTrue(try store.read(OperationJournal.self, name: file.lastPathComponent).hasUnsupportedVolumeTrashScope)
        XCTAssertFalse(try XCTUnwrap(recovery().pending().first { $0.id == journal.id }).canRestoreSource)
        XCTAssertThrowsError(try recovery().restoreSource(id: journal.id))
        XCTAssertThrowsError(try recovery().keepCopiesAndResolve(id: journal.id))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testRecoveryAcceptsHistoricalDeviceChangeOnlyForTheSameBoundVolume() throws {
        let (source, journal, before) = try interrupted()
        let file = store.base.appendingPathComponent("operation-\(journal.id.uuidString).json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var scope = try XCTUnwrap(object["volumeTrashScope"] as? [String: Any])
        // Simulate a journal written before a remount changed st_dev. This is
        // not a physical-remount qualification; UUID/inode/digest still bind it.
        func historicalDevice(_ value: Any?) throws -> [String: Any] {
            var identity = try XCTUnwrap(value as? [String: Any])
            identity["device"] = try XCTUnwrap(identity["device"] as? Int64) + 1_000
            return identity
        }
        scope["mountRootIdentity"] = try historicalDevice(scope["mountRootIdentity"])
        scope["itemIdentity"] = try historicalDevice(scope["itemIdentity"])
        object["volumeTrashScope"] = scope
        object["sourceIdentity"] = try historicalDevice(object["sourceIdentity"])
        object["trashIdentity"] = try historicalDevice(object["trashIdentity"])
        try JSONSerialization.data(withJSONObject: object, options: .sortedKeys).write(to: file)
        let historical = try store.read(OperationJournal.self, name: file.lastPathComponent)
        XCTAssertThrowsError(try XCTUnwrap(historical.volumeTrashScope).resolve(volumeProvider: provider), "A remounted active selection requires new review")
        volume = descriptor(disk, uuid: "DIFFERENT-VOLUME")
        XCTAssertThrowsError(try recovery().restoreSource(id: journal.id))
        volume = descriptor(disk)
        try recovery().restoreSource(id: journal.id)
        XCTAssertEqual(try FileTree.digest(source), before)
    }
    func testFailedFinderTrashNeverFallsBackToDeletion() throws {
        let item = try put("personal.txt"), scope = try VolumeTrashScope(item: item, volume: volume)
        var called = 0
        let action = PersonalActions(home: home, store: store, trashHandler: { _ in called += 1; throw CacheSSDError.message("Generated Finder refusal") }, busyCheck: { _, _ in [] }, volumeProvider: provider, finderTrashAvailable: { _ in true })
        XCTAssertThrowsError(try action.trash(item, scope: scope))
        XCTAssertEqual(called, 1); XCTAssertEqual(try String(contentsOf: item), "generated personal content")
        XCTAssertEqual(store.operations().first?.phase, .interrupted)
    }
    func testUnexpectedTrashOutsideBoundVolumeIsPreservedForFinderReview() throws {
        let item = try put("personal.txt"), scope = try VolumeTrashScope(item: item, volume: volume)
        let outside = root.appendingPathComponent("outside-result.txt")
        let action = PersonalActions(home: home, store: store, trashHandler: { source in try FileManager.default.moveItem(at: source, to: outside); return outside }, busyCheck: { _, _ in [] }, volumeProvider: provider, finderTrashAvailable: { _ in true })
        XCTAssertThrowsError(try action.trash(item, scope: scope))
        XCTAssertEqual(try String(contentsOf: outside), "generated personal content")
        let journal = try XCTUnwrap(store.operations().first)
        XCTAssertEqual(journal.trashPath, outside.path); XCTAssertNil(journal.trashRelativePath)
        XCTAssertFalse(try XCTUnwrap(recovery().pending().first { $0.id == journal.id }).canRestoreSource)
        XCTAssertThrowsError(try recovery().restoreSource(id: journal.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
    func testCancellationAndOperationLeasePreventScopedTrash() throws {
        let item = try put("personal.txt"), scope = try VolumeTrashScope(item: item, volume: volume)
        let cancellation = CancellationFlag(); cancellation.cancel()
        XCTAssertThrowsError(try actions().trash(item, scope: scope, cancellation: cancellation))
        let lease = try OperationLease(store: store)
        XCTAssertThrowsError(try actions().trash(item, scope: scope)); withExtendedLifetime(lease) {}
        XCTAssertEqual(trashCalls, 0); XCTAssertTrue(FileManager.default.fileExists(atPath: item.path))
    }
    func testLegacyJournalDecodesWithoutNewScopeFields() throws {
        let item = try put("legacy.txt"), journal = try OperationJournal(kind: "trash", source: item)
        let data = try JSONEncoder().encode(journal)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["volumeTrashScope"]); XCTAssertNil(object["trashRelativePath"])
        let decoded = try JSONDecoder().decode(OperationJournal.self, from: data)
        XCTAssertEqual(decoded.kind, "trash"); XCTAssertNil(decoded.volumeTrashScope)
    }
}
