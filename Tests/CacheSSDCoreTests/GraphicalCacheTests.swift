import XCTest
import Foundation
import Darwin
@testable import CacheSSDCore

final class GraphicalCacheTests: XCTestCase {
    var root: URL!
    var home: URL!
    var disk: URL!
    var store: Store!
    var volume: VolumeInfo!
    var available = true
    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-graphical-\(UUID().uuidString)")
        home = root.appendingPathComponent("home"); disk = root.appendingPathComponent("SSD")
        for path in [home!, disk!] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
        store = Store(base: root.appendingPathComponent("support"))
        volume = VolumeInfo(uuid: "GENERATED-GUI-SSD", name: "Generated SSD", path: disk.path, totalBytes: 10_000_000_000, freeBytes: 9_000_000_000, isInternal: false, isWritable: true)
        var settings = AppSettings(); settings.selectedVolumeUUID = volume.uuid; settings.shellIntegrationEnabled = true; try store.save(settings)
    }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at: root) } }
    func candidate() -> GraphicalCacheCandidate {
        GraphicalCacheCandidate(id: GraphicalCacheCatalog.chromeCacheID, applicationID: GraphicalCacheCatalog.chromeBundleID,
            applicationName: "Google Chrome", applicationVersion: "simulated", applicationURL: nil,
            sourceURL: home.appendingPathComponent(GraphicalCacheCatalog.chromeRelativePath), scopeLabel: "Generated cache directory", canTransfer: true, isSimulated: true)
    }
    func write(_ path: URL, _ text: String = "generated content") throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: path)
    }
    func seed() throws {
        try write(candidate().sourceURL.appendingPathComponent("Default/Cache/Cache_Data/generated-A"))
        for name in ["Cookies", "History", "Bookmarks", "Preferences"] {
            try write(home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/" + name), "generated protected " + name)
        }
    }
    func engine(observer: GraphicalCacheUsageObserver? = nil,
                checkpoint: @escaping (GraphicalCacheJournal) throws -> Void = { _ in }) -> GraphicalCacheMigrationEngine {
        GraphicalCacheMigrationEngine(store: store, home: home, volumeProvider: { _ in self.available ? self.volume : nil }, busyCheck: { _, _ in [] },
            applicationRunning: { _ in false }, usageObserver: observer, allowSimulatedCandidates: true, permittedRoot: root, checkpoint: checkpoint)
    }
    func simulatedObserver(_ candidate: GraphicalCacheCandidate, _ destination: URL, _ baseline: String) throws -> GraphicalCacheUsageEvidence? {
        let current = try GraphicalCacheActivity.fingerprint(destination)
        guard current != baseline else { return nil }
        return GraphicalCacheUsageEvidence(applicationVersion: candidate.applicationVersion ?? "simulated", processIDs: [-1],
            observedReadAccess: true, observedWriteAccess: true, metadataFingerprint: current, isSimulated: true)
    }
    func testFlagsWithoutRegistrationsRemainNoneAndDoNotCreateCache() throws {
        let before = try FileManager.default.contentsOfDirectory(atPath: store.base.path)
        XCTAssertEqual(engine().status(candidate: candidate()).state, .none)
        XCTAssertTrue(try engine().registrations().isEmpty)
        XCTAssertFalse(engine().hasUnsafeRecoveryRecords())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.base.path), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidate().sourceURL.path))
    }
    func testTransferWaitsForApplicationUseAndPreservesProfile() throws {
        try seed()
        let model = candidate(), result = try engine().transfer(candidate: model, volume: volume)
        XCTAssertEqual(result.state, .configuredNeedsReopen); XCTAssertFalse(result.sourceReleased)
        let registration = try XCTUnwrap(try engine().registrations().first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(registration.sourceQuarantine).path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: model.sourceURL.path), registration.linkTarget)
        XCTAssertEqual(engine().status(candidate: model).state, .configuredNeedsReopen)
        XCTAssertFalse(engine().hasUnsafeRecoveryRecords())
        for name in ["Cookies", "History", "Bookmarks", "Preferences"] {
            XCTAssertEqual(try String(contentsOf: home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/" + name)), "generated protected " + name)
        }
    }
    func testTouchedMarkerAloneDoesNotVerifyNativeApplicationUse() throws {
        try seed()
        let worker = engine(), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        let registration = try XCTUnwrap(try worker.registrations().first)
        try write(URL(fileURLWithPath: registration.linkTarget).appendingPathComponent("only-a-marker"))
        XCTAssertEqual(try worker.verifyUsage(candidate: model).state, .configuredNeedsReopen)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(registration.sourceQuarantine).path))
    }
    func testSimulatedEvidenceCanReleaseOnlyItsIsolatedOriginalAfterVerification() throws {
        try seed()
        let worker = engine(observer: simulatedObserver), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        let before = try XCTUnwrap(try worker.registrations().first)
        try write(URL(fileURLWithPath: before.linkTarget).appendingPathComponent("new-generated-cache-entry"))
        let status = try worker.verifyUsage(candidate: model)
        XCTAssertEqual(status.state, .ssdVerified); XCTAssertTrue(status.sourceReleased)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(before.sourceQuarantine).path))
        XCTAssertFalse(worker.hasUnsafeRecoveryRecords())
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: before.linkTarget).appendingPathComponent("Default/Cache/Cache_Data/generated-A").path))
    }
    func testSourceRetentionChoiceRemainsExplicitEvenAfterUse() throws {
        try seed()
        let worker = engine(observer: simulatedObserver), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume, releaseSource: false)
        let record = try XCTUnwrap(try worker.registrations().first)
        try write(URL(fileURLWithPath: record.linkTarget).appendingPathComponent("new-entry"))
        let status = try worker.verifyUsage(candidate: model)
        XCTAssertEqual(status.state, .ssdVerified); XCTAssertFalse(status.sourceReleased)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(record.sourceQuarantine).path))
    }
    func testMissingSourcePreparesRouteWithoutInventingUsage() throws {
        let worker = engine(), model = candidate()
        let result = try worker.transfer(candidate: model, volume: volume)
        XCTAssertEqual(result.state, .configuredNeedsReopen)
        XCTAssertTrue(try worker.registrations().first?.sourceReleased == true)
        XCTAssertEqual(try worker.verifyUsage(candidate: model).state, .configuredNeedsReopen)
        XCTAssertEqual(result.sourceLogicalBytes, 0)
    }
    func testMissingSSDHasHonestTemporaryStateWithoutMutatingRecords() throws {
        try seed()
        let worker = engine(), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        let before = try Data(contentsOf: store.base.appendingPathComponent("graphical-caches.json"))
        available = false
        let state = worker.status(candidate: model)
        XCTAssertEqual(state.state, .localTemporary)
        XCTAssertTrue(state.detail.contains("memória"))
        XCTAssertEqual(try Data(contentsOf: store.base.appendingPathComponent("graphical-caches.json")), before)
    }
    func testRestoreReturnsVerifiedCacheAndPreservesSSDCopy() throws {
        try seed()
        let worker = engine(), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        let record = try XCTUnwrap(try worker.registrations().first)
        try write(URL(fileURLWithPath: record.linkTarget).appendingPathComponent("new-B"), "generated new cache")
        XCTAssertEqual(try worker.restore(candidateID: model.id).state, .none)
        var metadata = stat(); XCTAssertEqual(lstat(model.sourceURL.path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & S_IFMT, mode_t(S_IFDIR))
        XCTAssertEqual(try String(contentsOf: model.sourceURL.appendingPathComponent("new-B")), "generated new cache")
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.linkTarget))
        XCTAssertTrue(try worker.registrations().isEmpty)
        XCTAssertTrue(worker.protectedPaths().contains(try XCTUnwrap(record.sourceQuarantine)))
        XCTAssertFalse(worker.hasUnsafeRecoveryRecords())
    }
    func testRestoreCanUsePreservedOriginalWhenSSDMissing() throws {
        try seed()
        let worker = engine(), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        available = false
        XCTAssertEqual(try worker.restore(candidateID: model.id).state, .none)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.sourceURL.appendingPathComponent("Default/Cache/Cache_Data/generated-A").path))
    }
    func testResumeUsesVolumeUUIDAfterRenameAndDoesNotMergeGenerations() throws {
        try seed()
        let worker = engine(), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        let original = try XCTUnwrap(try worker.registrations().first)
        let renamed = root.appendingPathComponent("Renamed SSD")
        try FileManager.default.moveItem(at: disk, to: renamed)
        volume = VolumeInfo(uuid: volume.uuid, name: "Renamed SSD", path: renamed.path, totalBytes: volume.totalBytes, freeBytes: volume.freeBytes, isInternal: false, isWritable: true)
        XCTAssertEqual(try worker.resumeExternal(candidateID: model.id).state, .configuredNeedsReopen)
        let updated = try XCTUnwrap(try worker.registrations().first)
        XCTAssertEqual(updated.relativeDestination, original.relativeDestination)
        XCTAssertEqual(updated.linkTarget, renamed.appendingPathComponent(original.relativeDestination).path)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: model.sourceURL.path), updated.linkTarget)
    }
    func testUnexpectedLocalCacheIsPreservedAndNeverSilentlyMerged() throws {
        try seed()
        let worker = engine(), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        try FileManager.default.removeItem(at: model.sourceURL)
        try write(model.sourceURL.appendingPathComponent("unexpected-new-data"))
        XCTAssertThrowsError(try worker.resumeExternal(candidateID: model.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.sourceURL.appendingPathComponent("unexpected-new-data").path))
    }
    func testFailureBeforeRedirectionKeepsOriginalAndCanResolveWithoutOverwrite() throws {
        enum Stop: Error { case injected }
        try seed()
        let worker = engine(checkpoint: { journal in if journal.phase == .copyVerified { throw Stop.injected } })
        XCTAssertThrowsError(try worker.transfer(candidate: candidate(), volume: volume))
        XCTAssertTrue(worker.hasUnsafeRecoveryRecords())
        let pending = try XCTUnwrap(try worker.pendingTransfers().first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate().sourceURL.appendingPathComponent("Default/Cache/Cache_Data/generated-A").path))
        XCTAssertEqual(try engine().recover(operationID: pending.id).state, .none)
        XCTAssertFalse(engine().hasUnsafeRecoveryRecords())
    }
    func testChangedQuarantinedOriginalCannotBeReleasedByUsageEvidence() throws {
        try seed()
        let worker = engine(observer: simulatedObserver, checkpoint: { journal in
            if journal.phase == .releasing, let quarantine = journal.sourceQuarantine {
                try self.write(quarantine.appendingPathComponent("late-unknown-data"), "preserve this change")
            }
        })
        let model = candidate(); _ = try worker.transfer(candidate: model, volume: volume)
        let record = try XCTUnwrap(try worker.registrations().first)
        try write(URL(fileURLWithPath: record.linkTarget).appendingPathComponent("new-B"))
        XCTAssertThrowsError(try worker.verifyUsage(candidate: model))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(record.sourceQuarantine).appendingPathComponent("late-unknown-data").path))
        XCTAssertTrue(worker.hasUnsafeRecoveryRecords())
    }
    func testDestinationAncestorRedirectionIsRefusedBeforeWritingOutside() throws {
        try seed()
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let worker = engine(checkpoint: { journal in
            if journal.phase == .preparing { try FileManager.default.createSymbolicLink(at: self.disk.appendingPathComponent("MacCaches"), withDestinationURL: outside) }
        })
        XCTAssertThrowsError(try worker.transfer(candidate: candidate(), volume: volume))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate().sourceURL.path))
    }
    func testGlobalLeaseExcludesGraphicalTransfer() throws {
        try seed()
        let lease = try OperationLease(store: store)
        XCTAssertThrowsError(try engine().transfer(candidate: candidate(), volume: volume))
        withExtendedLifetime(lease) {}
        XCTAssertTrue(try engine().registrations().isEmpty)
    }
    func testUnknownRegistryAndCompletedFutureJournalRemainUnsafeAndUnchanged() throws {
        let future = Data(#"{"schemaVersion":999,"installationID":"future","active":{}}"#.utf8)
        let path = store.base.appendingPathComponent("graphical-caches.json")
        try future.write(to: path)
        XCTAssertTrue(engine().hasUnsafeRecoveryRecords())
        XCTAssertThrowsError(try engine().registrations())
        XCTAssertEqual(try Data(contentsOf: path), future)
    }
    func testReadOnlyAccessOrDifferentProcessCannotProveApplicationUse() throws {
        let root = URL(fileURLWithPath: "/generated/SSD/cache")
        let readOnly = "p42\nf3\nar\ntREG\nn/generated/SSD/cache/entry\n"
        XCTAssertFalse(GraphicalCacheActivity.accesses(readOnly, destination: root, permittedPIDs: [42]).write)
        let wrong = "p99\nf3\nau\ntREG\nn/generated/SSD/cache/entry\n"
        XCTAssertFalse(GraphicalCacheActivity.accesses(wrong, destination: root, permittedPIDs: [42]).read)
        let directory = "p42\nf3\nau\ntDIR\nn/generated/SSD/cache/subfolder\n"
        XCTAssertFalse(GraphicalCacheActivity.accesses(directory, destination: root, permittedPIDs: [42]).read)
        let good = "p42\nf3\nau\ntREG\nn/generated/SSD/cache/entry\n"
        XCTAssertTrue(GraphicalCacheActivity.accesses(good, destination: root, permittedPIDs: [42]).read)
        XCTAssertTrue(GraphicalCacheActivity.accesses(good, destination: root, permittedPIDs: [42]).write)
    }
    func testReplacedDestinationCannotReleaseTheOnlyOriginal() throws {
        try seed()
        let worker = engine(observer: simulatedObserver), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        let record = try XCTUnwrap(try worker.registrations().first), destination = URL(fileURLWithPath: record.linkTarget)
        try FileManager.default.moveItem(at: destination, to: root.appendingPathComponent("old-data-preserved"))
        try write(destination.appendingPathComponent("substitute-data"))
        XCTAssertThrowsError(try worker.verifyUsage(candidate: model))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(record.sourceQuarantine).path))
        XCTAssertThrowsError(try worker.resumeExternal(candidateID: model.id))
    }
    func testRemovalBindsTheOpenedDirectoryBeforeAnyUnlink() throws {
        let target = root.appendingPathComponent("target"), old = root.appendingPathComponent("old-target")
        try write(target.appendingPathComponent("first")); let identity = try FileIdentity(target)
        try FileManager.default.moveItem(at: target, to: old)
        try write(target.appendingPathComponent("unknown"))
        let parent = try GraphicalCacheFiles.openParent(of: target, under: root, create: false); defer { close(parent) }
        XCTAssertThrowsError(try GraphicalCacheFiles.removeDirectory(target.lastPathComponent, parent: parent, expectedIdentity: identity, cancellation: CancellationFlag()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("unknown").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("first").path))
    }
    func testHardCrashDuringReleaseCannotHidePartialRecovery() throws {
        enum Stop: Error { case injected }
        try seed()
        let worker = engine(observer: simulatedObserver, checkpoint: { journal in if journal.phase == .releasing { throw Stop.injected } })
        let model = candidate(); _ = try worker.transfer(candidate: model, volume: volume)
        let record = try XCTUnwrap(try worker.registrations().first)
        try write(URL(fileURLWithPath: record.linkTarget).appendingPathComponent("new-B"))
        XCTAssertThrowsError(try worker.verifyUsage(candidate: model))
        var journal = try XCTUnwrap(try worker.pendingTransfers().first)
        journal.phase = .releasing; journal.interruptedAtPhase = nil
        try FileManager.default.removeItem(at: try XCTUnwrap(record.sourceQuarantine).appendingPathComponent("Default/Cache/Cache_Data/generated-A"))
        let name = "graphical-operation-" + journal.id.uuidString + ".json"
        try store.writeDurably(journal, name: name)
        let before = try Data(contentsOf: store.base.appendingPathComponent(name))
        XCTAssertThrowsError(try engine().recover(operationID: journal.id))
        XCTAssertEqual(try Data(contentsOf: store.base.appendingPathComponent(name)), before)
        XCTAssertTrue(engine().hasUnsafeRecoveryRecords())
        XCTAssertEqual(engine().status(candidate: model).state, .error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: record.linkTarget).appendingPathComponent("Default/Cache/Cache_Data/generated-A").path))
    }
    func testUnknownOperationIsNotRewrittenEvenWhenLabelledCompleted() throws {
        try seed(); let worker = engine(), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        let record = try XCTUnwrap(try worker.registrations().first)
        let name = "graphical-operation-" + record.id.uuidString + ".json"
        var journal = try store.read(GraphicalCacheJournal.self, name: name)
        journal.operation = "future-operation"; journal.phase = .completed
        try store.writeDurably(journal, name: name)
        let before = try Data(contentsOf: store.base.appendingPathComponent(name))
        XCTAssertTrue(worker.hasUnsafeRecoveryRecords()); XCTAssertThrowsError(try worker.recover(operationID: journal.id))
        XCTAssertEqual(try Data(contentsOf: store.base.appendingPathComponent(name)), before)
    }
    func testLocalOriginalRestoreDoesNotNeedAnotherCacheSizedAllocation() throws {
        try seed(); var free: Int64 = 9_000_000_000
        let worker = GraphicalCacheMigrationEngine(store: store, home: home, volumeProvider: { _ in self.available ? self.volume : nil },
            busyCheck: { _, _ in [] }, applicationRunning: { _ in false }, allowSimulatedCandidates: true, permittedRoot: root, freeBytes: { _ in free })
        let model = candidate(); _ = try worker.transfer(candidate: model, volume: volume)
        let record = try XCTUnwrap(try worker.registrations().first)
        let identity = try FileIdentity(try XCTUnwrap(record.sourceQuarantine))
        available = false; free = 0
        XCTAssertEqual(try worker.restore(candidateID: model.id).state, .none)
        let restored = try FileIdentity(model.sourceURL)
        XCTAssertEqual(restored.device, identity.device); XCTAssertEqual(restored.inode, identity.inode)
    }
    func testRecoveryAfterLocalRestoreSwapRemovesOnlyItsHeldLink() throws {
        try seed(); let worker = engine(), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        let record = try XCTUnwrap(try worker.registrations().first)
        let quarantine = try XCTUnwrap(record.sourceQuarantine)
        let identity = try FileIdentity(quarantine), operation = UUID()
        var journal = GraphicalCacheJournal(schemaVersion: 1, id: operation, candidateID: model.id,
            sourceURL: model.sourceURL, volumeUUID: volume.uuid, relativeDestination: record.relativeDestination,
            sourceIdentity: identity, sourceDigest: record.sourceDigest, sourceQuarantine: quarantine, stagingURL: nil,
            phase: .restoring, detail: "Generated hard-crash boundary", registration: record, startedAt: Date(), updatedAt: Date())
        journal.operation = "restore"; journal.publicationIdentity = identity; journal.heldLinkName = quarantine.lastPathComponent
        let parent = try GraphicalCacheFiles.openParent(of: model.sourceURL, under: home, create: false); defer { close(parent) }
        XCTAssertEqual(renameatx_np(parent, quarantine.lastPathComponent, parent, model.sourceURL.lastPathComponent, UInt32(RENAME_SWAP)), 0)
        try store.writeDurably(journal, name: "graphical-operation-" + operation.uuidString + ".json")
        available = false
        XCTAssertEqual(try worker.recover(operationID: operation).state, .none)
        XCTAssertTrue(try worker.registrations().isEmpty)
        var missing = stat(); XCTAssertEqual(lstat(quarantine.path, &missing), -1); XCTAssertEqual(errno, ENOENT)
        XCTAssertEqual(try String(contentsOf: model.sourceURL.appendingPathComponent("Default/Cache/Cache_Data/generated-A")), "generated content")
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: record.linkTarget).appendingPathComponent("Default/Cache/Cache_Data/generated-A").path))
    }
    func testFutureMetadataPolicyPreservesJournalAndBlocksRegistry() throws {
        try seed(); let worker = engine(), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        let record = try XCTUnwrap(try worker.registrations().first)
        let journalName = "graphical-operation-" + record.id.uuidString + ".json"
        var journal = try store.read(GraphicalCacheJournal.self, name: journalName)
        journal.phase = .completed
        journal.metadataVerification = GraphicalCacheVerificationProof(policyVersion: 99, verifiedEntries: 1, quarantine: [])
        try store.writeDurably(journal, name: journalName)
        let before = try Data(contentsOf: store.base.appendingPathComponent(journalName))
        XCTAssertTrue(journal.isUnsupported); XCTAssertTrue(worker.hasUnsafeRecoveryRecords())
        XCTAssertTrue(worker.protectedPaths().contains(model.sourceURL))
        XCTAssertTrue(worker.protectedPaths().contains(try XCTUnwrap(record.sourceQuarantine)))
        XCTAssertThrowsError(try worker.recover(operationID: record.id))
        XCTAssertEqual(try Data(contentsOf: store.base.appendingPathComponent(journalName)), before)
        let registryURL = store.base.appendingPathComponent("graphical-caches.json")
        var registry = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any])
        var active = try XCTUnwrap(registry["active"] as? [String: Any])
        var entry = try XCTUnwrap(active[model.id] as? [String: Any])
        entry["metadataVerification"] = ["policyVersion": 99, "verifiedEntries": 1, "quarantine": []]
        active[model.id] = entry; registry["active"] = active
        let future = try JSONSerialization.data(withJSONObject: registry, options: [.sortedKeys])
        try future.write(to: registryURL)
        XCTAssertThrowsError(try worker.registrations())
        XCTAssertTrue(worker.protectedPaths().contains(URL(fileURLWithPath: record.linkTarget)))
        XCTAssertTrue(worker.protectedPaths().contains(try XCTUnwrap(record.sourceQuarantine)))
        XCTAssertEqual(try Data(contentsOf: registryURL), future)
    }
    func testUntrustedBundleCannotQualifyByCopyingChromeMetadata() throws {
        let bundle = root.appendingPathComponent("Google Chrome.app")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let metadata: [String: Any] = ["CFBundleIdentifier": GraphicalCacheCatalog.chromeBundleID, "CFBundleShortVersionString": "157.0.8103.39"]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        XCTAssertFalse(GraphicalCacheCatalog.chromeSignatureIsQualified(bundle))
    }
    func testCancelledFingerprintAndRemovalPreserveData() throws {
        try seed(); let token = CancellationFlag(); token.cancel()
        XCTAssertThrowsError(try GraphicalCacheActivity.fingerprint(candidate().sourceURL, cancellation: token))
        let source = candidate().sourceURL, identity = try FileIdentity(source)
        let parent = try GraphicalCacheFiles.openParent(of: source, under: home, create: false); defer { close(parent) }
        XCTAssertThrowsError(try GraphicalCacheFiles.removeDirectory(source.lastPathComponent, parent: parent, expectedIdentity: identity, cancellation: token))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("Default/Cache/Cache_Data/generated-A").path))
    }
    func testVerifiedCacheRenameRequiresExplicitRetargetBeforeClaimingSSDUse() throws {
        try seed(); let worker = engine(observer: simulatedObserver), model = candidate()
        _ = try worker.transfer(candidate: model, volume: volume)
        let record = try XCTUnwrap(try worker.registrations().first)
        try write(URL(fileURLWithPath: record.linkTarget).appendingPathComponent("new-B"))
        XCTAssertEqual(try worker.verifyUsage(candidate: model).state, .ssdVerified)
        let renamed = root.appendingPathComponent("Renamed Volume")
        try FileManager.default.moveItem(at: disk, to: renamed)
        volume = VolumeInfo(uuid: volume.uuid, name: "Renamed Volume", path: renamed.path, totalBytes: volume.totalBytes, freeBytes: volume.freeBytes, isInternal: false, isWritable: true)
        let status = worker.status(candidate: model)
        XCTAssertEqual(status.state, .localTemporary)
        XCTAssertTrue(status.detail.contains("retomada"))
    }
    func testUnknownParentLinkIsNotNormalizedIntoAnEligibleCache() throws {
        let documents = home.appendingPathComponent("Documents")
        try write(documents.appendingPathComponent("Chrome/private-project"), "preserve non-cache data")
        let parent = home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: parent.appendingPathComponent("Google"), withDestinationURL: documents)
        XCTAssertThrowsError(try engine().transfer(candidate: candidate(), volume: volume))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: disk.path).isEmpty)
        XCTAssertEqual(try String(contentsOf: documents.appendingPathComponent("Chrome/private-project")), "preserve non-cache data")
    }
    func testSystemTempAliasAndMissingDirectoryHintRemainScoped() throws {
        let physical = Paths.physicalURL(FileManager.default.temporaryDirectory).appendingPathComponent("DiskWing-gui-alias-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: physical, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: physical) }
        let aliasPath = physical.path.hasPrefix("/private/var/") ? String(physical.path.dropFirst("/private".count)) : physical.path
        let alias = URL(fileURLWithPath: aliasPath, isDirectory: true)
        let localHome = alias.appendingPathComponent("home", isDirectory: true).standardizedFileURL
        let localDisk = alias.appendingPathComponent("SSD", isDirectory: true)
        for path in [localHome, localDisk] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false) }
        let localStore = Store(base: alias.appendingPathComponent("support"))
        let localVolume = VolumeInfo(uuid: "GENERATED-ALIAS", name: "Generated", path: localDisk.path, totalBytes: 10_000_000_000, freeBytes: 9_000_000_000, isInternal: false, isWritable: true)
        let model = GraphicalCacheCandidate(id: GraphicalCacheCatalog.chromeCacheID, applicationID: GraphicalCacheCatalog.chromeBundleID,
            applicationName: "Generated Chrome", applicationVersion: "simulated", applicationURL: nil,
            sourceURL: URL(fileURLWithPath: localHome.appendingPathComponent(GraphicalCacheCatalog.chromeRelativePath).path, isDirectory: true),
            scopeLabel: "Generated missing cache", canTransfer: true, isSimulated: true)
        let worker = GraphicalCacheMigrationEngine(store: localStore, home: localHome, volumeProvider: { _ in localVolume },
            busyCheck: { _, _ in [] }, applicationRunning: { _ in false }, allowSimulatedCandidates: true, permittedRoot: alias)
        XCTAssertEqual(try worker.transfer(candidate: model, volume: localVolume).state, .configuredNeedsReopen)
        XCTAssertEqual(worker.status(candidate: model).state, .configuredNeedsReopen)
    }
}
