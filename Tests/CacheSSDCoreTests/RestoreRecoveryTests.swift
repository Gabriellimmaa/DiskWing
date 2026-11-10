import XCTest
import Darwin
@testable import CacheSSDCore

final class RestoreRecoveryTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(base).appendingPathComponent("DiskWing-restore-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    struct Fixture {
        let home: URL; let store: Store; let tool: CacheDescriptor; let volume: VolumeInfo; let external: URL; let expected: String
    }
    func fixture() throws -> Fixture {
        let directory = root.appendingPathComponent(UUID().uuidString), home = directory.appendingPathComponent("home"), store = Store(base: directory.appendingPathComponent("support"))
        let tool = try XCTUnwrap(CacheCatalog.find("npm", home: home))
        try FileManager.default.createDirectory(at: tool.source, withIntermediateDirectories: true)
        try Data("preserved cache data".utf8).write(to: tool.source.appendingPathComponent("artifact"))
        let expected = try FileTree.digest(tool.source, workspace: root)
        let disk = directory.appendingPathComponent("fixture-volume"); try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
        let volume = VolumeInfo(uuid: "GENERATED-RESTORE-VOLUME", name: "Fixture", path: disk.path, totalBytes: 1_000_000_000_000, freeBytes: 900_000_000_000, isInternal: false, isWritable: true)
        var settings = AppSettings(); settings.selectedVolumeUUID = volume.uuid; try store.save(settings)
        _ = try MigrationEngine(store: store, home: home, volumeProvider: { _ in volume }, verifyNative: false).migrate(toolID: "npm", removeLocal: true)
        let location = try XCTUnwrap(store.settings().locations["npm"])
        let external = tool.payload(at: disk.appendingPathComponent(location.relativePath))
        return Fixture(home: home, store: store, tool: tool, volume: volume, external: external, expected: expected)
    }
    func interrupted(_ fixture: Fixture, at phase: OperationPhase) throws -> OperationJournal {
        let engine = MigrationEngine(store: fixture.store, home: fixture.home, volumeProvider: { _ in fixture.volume }, verifyNative: false, checkpoint: { record in
            if record.kind == "restore" && record.phase == phase { throw CacheSSDError.message("Injected restore interruption") }
        })
        XCTAssertThrowsError(try engine.restore(toolID: "npm"))
        return try XCTUnwrap(fixture.store.operations().first(where: { $0.kind == "restore" }))
    }
    func testRestoreRecoveryCompletesEveryBoundaryAndRemainsIdempotent() throws {
        for phase in [OperationPhase.preparing, .verifying, .copying, .copyVerified, .publishing, .published, .completed] {
            let f = try fixture(), record = try interrupted(f, at: phase)
            let manager = RecoveryManager(store: f.store, home: f.home)
            let assessment = try XCTUnwrap(manager.pending().first(where: { $0.id == record.id }))
            XCTAssertEqual(assessment.recoveryAction, .finishRestore, phase.rawValue)
            try manager.recover(id: record.id)
            XCTAssertEqual(try FileTree.digest(f.tool.source, workspace: root), f.expected, phase.rawValue)
            XCTAssertEqual(try FileTree.digest(f.external, workspace: root), f.expected, phase.rawValue)
            XCTAssertNil(f.store.settings().locations["npm"])
            XCTAssertEqual(f.store.operations().first(where: { $0.id == record.id })?.phase, .resolved)
            let bytes = try Data(contentsOf: f.store.base.appendingPathComponent("operation-\(record.id.uuidString).json"))
            try manager.restoreSource(id: record.id)
            XCTAssertEqual(try Data(contentsOf: f.store.base.appendingPathComponent("operation-\(record.id.uuidString).json")), bytes)
        }
    }
    func testPartialStagingIsPreservedAndItsOldJournalRemainsAvailable() throws {
        let f = try fixture(), record = try interrupted(f, at: .copying)
        let partial = URL(fileURLWithPath: try XCTUnwrap(record.staging))
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        let evidence = partial.appendingPathComponent("partial"); try Data("keep partial bytes".utf8).write(to: evidence)
        try RecoveryManager(store: f.store, home: f.home).recover(id: record.id)
        XCTAssertEqual(try String(contentsOf: evidence), "keep partial bytes")
        let snapshots = try FileManager.default.contentsOfDirectory(at: f.store.base, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("restore-recovery-before-") }
        XCTAssertFalse(snapshots.isEmpty)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertTrue(try snapshots.map { try decoder.decode(OperationJournal.self, from: Data(contentsOf: $0)) }.contains { $0.id == record.id && $0.staging == partial.path })
        XCTAssertEqual(f.store.operations().filter { $0.id == record.id }.count, 1)
    }
    func testVerifiedStagingRecoversWithoutAnAvailableExternalCopy() throws {
        let f = try fixture(), record = try interrupted(f, at: .copyVerified)
        let retained = f.external.deletingLastPathComponent().appendingPathComponent("retained-external")
        try FileManager.default.moveItem(at: f.external, to: retained)
        try RecoveryManager(store: f.store, home: f.home).recover(id: record.id)
        XCTAssertEqual(try FileTree.digest(f.tool.source, workspace: root), f.expected)
        XCTAssertEqual(try FileTree.digest(retained, workspace: root), f.expected)
    }
    func testPublishedCopyCompletesConfigurationWithoutExternalAccess() throws {
        let f = try fixture(), record = try interrupted(f, at: .published)
        let retained = f.external.deletingLastPathComponent().appendingPathComponent("retained-external")
        try FileManager.default.moveItem(at: f.external, to: retained)
        let identity = try FileIdentity(f.tool.source)
        try RecoveryManager(store: f.store, home: f.home).recover(id: record.id)
        XCTAssertEqual(try FileIdentity(f.tool.source), identity)
        XCTAssertNil(f.store.settings().locations["npm"])
        XCTAssertEqual(try FileTree.digest(retained, workspace: root), f.expected)
    }
    func testUnreadableConfigurationIsPreservedAndDoesNotEnableRecovery() throws {
        let f = try fixture(), record = try interrupted(f, at: .published)
        let path = f.store.base.appendingPathComponent("settings.json"), bytes = Data("invalid settings; preserve".utf8)
        try bytes.write(to: path)
        let manager = RecoveryManager(store: f.store, home: f.home)
        XCTAssertFalse(try XCTUnwrap(manager.pending().first(where: { $0.id == record.id })).canRestoreSource)
        XCTAssertThrowsError(try manager.recover(id: record.id))
        XCTAssertEqual(try Data(contentsOf: path), bytes)
        XCTAssertEqual(try FileTree.digest(f.tool.source, workspace: root), f.expected)
        XCTAssertEqual(try FileTree.digest(f.external, workspace: root), f.expected)
    }
    func testPublishedEmptyCacheCanReconcileWithoutAnExternalCopy() throws {
        let f = try fixture()
        try FileManager.default.removeItem(at: f.external.appendingPathComponent("artifact"))
        let expected = try FileTree.digest(f.external, workspace: root), record = try interrupted(f, at: .published)
        let retained = f.external.deletingLastPathComponent().appendingPathComponent("retained-empty")
        try FileManager.default.moveItem(at: f.external, to: retained)
        try RecoveryManager(store: f.store, home: f.home).recover(id: record.id)
        XCTAssertEqual(try FileTree.digest(f.tool.source, workspace: root), expected)
        XCTAssertNil(f.store.settings().locations["npm"])
    }
    func testCancelledRecoveryRetainsARecoverableJournalAndOriginal() throws {
        let f = try fixture(), record = try interrupted(f, at: .copying), token = CancellationFlag()
        let manager = RecoveryManager(store: f.store, home: f.home, checkpoint: { if $0.phase == .copying { token.cancel() } })
        XCTAssertThrowsError(try manager.recover(id: record.id, cancellation: token))
        XCTAssertEqual(f.store.operations().first(where: { $0.id == record.id })?.phase, .cancelled)
        XCTAssertEqual(try FileTree.digest(f.external, workspace: root), f.expected)
        XCTAssertNotNil(f.store.settings().locations["npm"])
        try RecoveryManager(store: f.store, home: f.home).recover(id: record.id)
        XCTAssertEqual(try FileTree.digest(f.tool.source, workspace: root), f.expected)
    }
    func testReappearingAndDanglingLocalTargetsAreNeverReplaced() throws {
        for dangling in [false, true] {
            let f = try fixture(), record = try interrupted(f, at: .copyVerified)
            if dangling {
                try FileManager.default.removeItem(at: f.tool.source)
                try FileManager.default.createSymbolicLink(atPath: f.tool.source.path, withDestinationPath: f.home.appendingPathComponent("missing").path)
            } else { try Data("new local bytes".utf8).write(to: f.tool.source.appendingPathComponent("new")) }
            XCTAssertThrowsError(try RecoveryManager(store: f.store, home: f.home).recover(id: record.id))
            if dangling { XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: f.tool.source.path), f.home.appendingPathComponent("missing").path) }
            else { XCTAssertEqual(try String(contentsOf: f.tool.source.appendingPathComponent("new")), "new local bytes") }
            XCTAssertNotNil(f.store.settings().locations["npm"])
            XCTAssertEqual(try FileTree.digest(f.external, workspace: root), f.expected)
        }
    }
    func testChangedExternalAndNewConfigurationArePreserved() throws {
        let f = try fixture(), record = try interrupted(f, at: .copying)
        try Data("changed external bytes".utf8).write(to: f.external.appendingPathComponent("artifact"))
        XCTAssertThrowsError(try RecoveryManager(store: f.store, home: f.home).recover(id: record.id))
        XCTAssertEqual(try String(contentsOf: f.external.appendingPathComponent("artifact")), "changed external bytes")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.tool.source.path).isEmpty)
        let other = try fixture(), published = try interrupted(other, at: .published)
        var settings = other.store.settings(); settings.locations["npm"]?.relativePath += "-new-generation"; try other.store.save(settings)
        let before = try Data(contentsOf: other.store.base.appendingPathComponent("settings.json"))
        XCTAssertThrowsError(try RecoveryManager(store: other.store, home: other.home).recover(id: published.id))
        XCTAssertEqual(try Data(contentsOf: other.store.base.appendingPathComponent("settings.json")), before)
        XCTAssertEqual(try FileTree.digest(other.tool.source, workspace: root), other.expected)
    }
    func testDifferentVolumeWithTheSameRelativePathIsNotReconciled() throws {
        for phase in [OperationPhase.copying, .published] {
            let f = try fixture(), record = try interrupted(f, at: phase)
            XCTAssertEqual(record.sourceVolumeUUID, f.volume.uuid)
            var settings = f.store.settings(); settings.locations["npm"]?.volumeUUID = "OTHER-GENERATED-VOLUME"
            try f.store.save(settings)
            let configPath = f.store.base.appendingPathComponent("settings.json")
            let recordPath = f.store.base.appendingPathComponent("operation-\(record.id.uuidString).json")
            let before = try Data(contentsOf: configPath), journalBytes = try Data(contentsOf: recordPath)
            let manager = RecoveryManager(store: f.store, home: f.home)
            XCTAssertFalse(try XCTUnwrap(manager.pending().first(where: { $0.id == record.id })).canRestoreSource)
            XCTAssertThrowsError(try manager.recover(id: record.id))
            XCTAssertEqual(try Data(contentsOf: configPath), before)
            XCTAssertEqual(try Data(contentsOf: recordPath), journalBytes)
            XCTAssertEqual(try FileTree.digest(f.external, workspace: root), f.expected)
        }
    }
    func testLegacyRestoreWithoutVolumeProofIsReadableButCannotClearConfiguredRoute() throws {
        let f = try fixture(), record = try interrupted(f, at: .published)
        let path = f.store.base.appendingPathComponent("operation-\(record.id.uuidString).json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String:Any])
        json.removeValue(forKey: "sourceVolumeUUID")
        let legacy = try JSONSerialization.data(withJSONObject: json); try legacy.write(to: path)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OperationJournal.self, from: legacy)
        XCTAssertNil(decoded.sourceVolumeUUID); XCTAssertEqual(decoded.sourceDigest, record.sourceDigest)
        let configPath = f.store.base.appendingPathComponent("settings.json"), settings = try Data(contentsOf: configPath)
        let manager = RecoveryManager(store: f.store, home: f.home)
        XCTAssertFalse(try XCTUnwrap(manager.pending().first(where: { $0.id == record.id })).canRestoreSource)
        XCTAssertThrowsError(try manager.recover(id: record.id))
        XCTAssertEqual(try Data(contentsOf: path), legacy)
        XCTAssertEqual(try Data(contentsOf: configPath), settings)
        XCTAssertEqual(try FileTree.digest(f.tool.source, workspace: root), f.expected)
    }
    func testRecoveryCanBeInterruptedAfterPublicationOrConfigurationAndRetried() throws {
        for phase in [OperationPhase.published, .resolved] {
            let f = try fixture(), record = try interrupted(f, at: .copying)
            let manager = RecoveryManager(store: f.store, home: f.home, checkpoint: { if $0.phase == phase { throw CacheSSDError.message("Injected recovery stop") } })
            XCTAssertThrowsError(try manager.recover(id: record.id))
            XCTAssertEqual(try FileTree.digest(f.tool.source, workspace: root), f.expected)
            try RecoveryManager(store: f.store, home: f.home).recover(id: record.id)
            XCTAssertNil(f.store.settings().locations["npm"])
            XCTAssertEqual(f.store.operations().first(where: { $0.id == record.id })?.phase, .resolved)
        }
    }
    func testNormalRestorePreservesUnrelatedConfigurationAndConflictingNewGenerations() throws {
        for conflict in [false, true] {
            let f = try fixture()
            let engine = MigrationEngine(store: f.store, home: f.home, volumeProvider: { _ in f.volume }, verifyNative: false, checkpoint: { record in
                if record.kind == "restore" && record.phase == .published {
                    var latest = f.store.settings(); latest.useExternal = false; latest.selectedVolumeUUID = "OTHER-GENERATED-VOLUME"
                    if conflict { latest.locations["npm"]?.relativePath += "-new-generation" }
                    try f.store.save(latest)
                }
            })
            if conflict { XCTAssertThrowsError(try engine.restore(toolID: "npm")) }
            else { try engine.restore(toolID: "npm") }
            XCTAssertFalse(f.store.settings().useExternal)
            XCTAssertEqual(f.store.settings().selectedVolumeUUID, "OTHER-GENERATED-VOLUME")
            if conflict { XCTAssertTrue(f.store.settings().locations["npm"]?.relativePath.hasSuffix("-new-generation") == true) }
            else { XCTAssertNil(f.store.settings().locations["npm"]) }
            XCTAssertEqual(try FileTree.digest(f.tool.source, workspace: root), f.expected)
            XCTAssertEqual(try FileTree.digest(f.external, workspace: root), f.expected)
        }
    }
    func testPublicationCheckpointCannotOverwriteAConcurrentLocalWrite() throws {
        let f = try fixture(), record = try interrupted(f, at: .copying)
        let manager = RecoveryManager(store: f.store, home: f.home, checkpoint: { if $0.phase == .publishing { try Data("concurrent bytes".utf8).write(to: f.tool.source.appendingPathComponent("new")) } })
        XCTAssertThrowsError(try manager.recover(id: record.id))
        XCTAssertEqual(try String(contentsOf: f.tool.source.appendingPathComponent("new")), "concurrent bytes")
        XCTAssertNotNil(f.store.settings().locations["npm"])
        XCTAssertEqual(try FileTree.digest(f.external, workspace: root), f.expected)
    }
    func testCorruptFutureUnknownAndMismatchedRecordsAreNotExecuted() throws {
        let f = try fixture(), record = try interrupted(f, at: .copying)
        let path = f.store.base.appendingPathComponent("operation-\(record.id.uuidString).json")
        let original = try Data(contentsOf: path)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        for change in ["schemaVersion", "kind", "destination"] {
            var changed = json
            if change == "schemaVersion" { changed[change] = 99 }
            if change == "kind" { changed[change] = "future-operation" }
            if change == "destination" { changed[change] = f.home.appendingPathComponent("Documents/unrelated").path }
            let bytes = try JSONSerialization.data(withJSONObject: changed); try bytes.write(to: path)
            let manager = RecoveryManager(store: f.store, home: f.home)
            XCTAssertFalse(try XCTUnwrap(manager.pending().first(where: { $0.id == record.id })).canRestoreSource)
            XCTAssertThrowsError(try manager.recover(id: record.id))
            XCTAssertThrowsError(try manager.keepCopiesAndResolve(id: record.id))
            XCTAssertEqual(try Data(contentsOf: path), bytes)
        }
        try Data("unreadable journal".utf8).write(to: path)
        XCTAssertTrue(RecoveryManager(store: f.store, home: f.home).pending().allSatisfy { $0.id != record.id })
        XCTAssertTrue(f.store.unreadableOperationRecords().contains(path.lastPathComponent))
        XCTAssertEqual(try String(contentsOf: path), "unreadable journal")
    }
}
