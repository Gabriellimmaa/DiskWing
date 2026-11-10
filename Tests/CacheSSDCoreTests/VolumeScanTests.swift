import XCTest
import Foundation
import Darwin
@testable import CacheSSDCore

final class VolumeScanTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var database: URL!
    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-volume-\(UUID().uuidString)")
        source = root.appendingPathComponent("source"); database = root.appendingPathComponent("support/index.sqlite")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    @discardableResult private func file(_ relative: String, bytes: Int = 12, at base: URL? = nil) throws -> URL {
        let url = (base ?? source).appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: bytes).write(to: url); return url
    }
    private func target() throws -> VolumeScanTarget { try VolumeScanTarget.folder(source, name: "Generated volume") }
    private var unlimited: IndexStoragePolicy { IndexStoragePolicy(maximumBytes: nil, minimumFreeBytes: 0) }

    func testVolumeScanIncludesHiddenAndDeepContentWithPaginatedGlobalSearch() throws {
        try file(".hidden", bytes: 7)
        var directory = source!
        for _ in 0..<90 { directory.appendPathComponent("d"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        try file("deep.txt", bytes: 19, at: directory)
        for n in 0..<650 { try file("many/file-\(n)", bytes: 3) }
        let index = try ScanIndex(url: database), report = try VolumeScanner(home: root).scan(target(), index: index, policy: unlimited)
        XCTAssertFalse(report.isPartial); XCTAssertEqual(report.root.fileCount, 652); XCTAssertEqual(report.root.logicalBytes, 1976)
        XCTAssertEqual(try index.page(sessionID: report.id, search: "deep.txt").total, 1)
        let parent = source.appendingPathComponent("many").path
        let summary = try index.childrenSummary(sessionID: report.id, parent: parent, offset: 0, limit: 128)
        XCTAssertEqual(summary.page.total, 650); XCTAssertEqual(summary.page.items.count, 128)
        XCTAssertEqual(summary.logicalBytes, 1950); XCTAssertEqual(summary.omittedCount, 522)
        XCTAssertEqual(summary.omittedLogicalBytes + summary.page.items.reduce(0) { $0 + $1.logicalBytes }, 1950)
        XCTAssertEqual(try index.page(sessionID: report.id, parent: parent, offset: 600).items.count, 50)
    }
    func testDiskBackedHardlinkAllocationAndLinkMetadataDoNotDuplicateTargets() throws {
        let original = try file("original", bytes: 4097)
        XCTAssertEqual(link(original.path, source.appendingPathComponent("hardlink").path), 0)
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("symbolic").path, withDestinationPath: "original")
        let index = try ScanIndex(url: database), report = try VolumeScanner(home: root).scan(target(), index: index, policy: unlimited)
        var metadata = stat(); XCTAssertEqual(lstat(original.path, &metadata), 0)
        XCTAssertEqual(report.root.logicalBytes, 8194); XCTAssertEqual(report.root.allocatedBytes, Int64(metadata.st_blocks) * 512)
        XCTAssertEqual(report.root.fileCount, 2)
        let item = try XCTUnwrap(try index.page(sessionID: report.id, search: "symbolic").items.first)
        XCTAssertTrue(item.isSymbolicLink); XCTAssertEqual(item.logicalBytes, 0)
        XCTAssertNil(try index.sourceLocation(sessionID: report.id, path: item.path))
    }
    func testPausedDirectoryResumesAfterReopenAndRevalidatesRenamedAndChangedEntries() throws {
        for n in 0..<180 { try file("folder/file-\(n)", bytes: 2) }
        var id: UUID!
        do {
            let index = try ScanIndex(url: database)
            let report = try VolumeScanner(home: root, maximumEntriesPerPass: 80).scan(target(), index: index, policy: unlimited)
            id = report.id; XCTAssertTrue(report.isPartial)
            XCTAssertEqual(try index.session(id: id)?.state, "paused")
        }
        try FileManager.default.moveItem(at: source.appendingPathComponent("folder"), to: source.appendingPathComponent("renamed"))
        try file("renamed/file-0", bytes: 97)
        try file(".new", bytes: 31)
        let index = try ScanIndex(url: database)
        XCTAssertEqual(try index.resumableVolumeSession(targetID: target().id), id)
        let report = try VolumeScanner(home: root).scan(target(), index: index, resumeSessionID: id, policy: unlimited)
        XCTAssertFalse(report.isPartial); XCTAssertEqual(report.root.fileCount, 181); XCTAssertEqual(report.root.logicalBytes, 486)
        XCTAssertEqual(try index.page(sessionID: id, search: "folder/").total, 0)
        XCTAssertEqual(try index.page(sessionID: id, search: "renamed/file-0").total, 1)
    }
    func testCompletedDirectoryContentIsRevalidatedEvenWhenParentMtimeDoesNotChange() throws {
        try file("a/done", bytes: 9)
        for n in 0..<90 { try file("z/file-\(n)", bytes: 1) }
        let index = try ScanIndex(url: database)
        let partial = try VolumeScanner(home: root, maximumEntriesPerPass: 30).scan(target(), index: index, policy: unlimited)
        XCTAssertTrue(partial.isPartial)
        let parent = source.appendingPathComponent("a"), before = try FileIdentity(parent)
        try file("a/done", bytes: 21)
        XCTAssertEqual(try FileIdentity(parent), before)
        let report = try VolumeScanner(home: root).scan(target(), index: index, resumeSessionID: partial.id, policy: unlimited)
        XCTAssertFalse(report.isPartial); XCTAssertEqual(report.root.logicalBytes, 111); XCTAssertEqual(report.root.fileCount, 91)
    }
    func testStorageFloorPausesDurablyWithoutPretendingCompleteOrMovingOldIndex() throws {
        try file("kept", bytes: 14)
        let oldIndex = root.appendingPathComponent("old-index.sqlite"); try Data("preserved old index".utf8).write(to: oldIndex)
        let index = try ScanIndex(url: database)
        let report = try VolumeScanner(home: root, freeBytes: { _ in 0 }).scan(target(), index: index, policy: .externalSSD)
        XCTAssertTrue(report.isPartial); XCTAssertEqual(try index.session(id: report.id)?.state, "paused")
        XCTAssertEqual(try String(contentsOf: oldIndex), "preserved old index")
        let resumed = try VolumeScanner(home: root).scan(target(), index: index, resumeSessionID: report.id, policy: unlimited)
        XCTAssertFalse(resumed.isPartial); XCTAssertEqual(resumed.root.logicalBytes, 14)
    }
    func testIndexAndAdditionalPrivateRootsAreExplicitlyExcluded() throws {
        try file("visible", bytes: 7)
        let privateDirectory = source.appendingPathComponent("private")
        try file("private/credential-record", bytes: 47)
        let index = try ScanIndex(url: source.appendingPathComponent("index-records/index.sqlite"))
        let report = try VolumeScanner(home: root, excludedRoots: [privateDirectory]).scan(target(), index: index, policy: unlimited)
        XCTAssertTrue(report.isPartial); XCTAssertEqual(report.root.logicalBytes, 7)
        XCTAssertTrue(try index.page(sessionID: report.id, search: "credential-record").items.isEmpty)
        XCTAssertTrue(try index.page(sessionID: report.id, search: "index.sqlite").items.isEmpty)
        XCTAssertEqual(try index.page(sessionID: report.id, search: "index-records").items.first?.coverage, .unknown)
        XCTAssertNil(try index.resumableVolumeSession(targetID: target().id), "Intentional exclusions are visible, rather than an endless continuation with no pending work")
    }
    func testGroupUnifiesProvenCanonicalEntriesAndKeepsUnmappedDataVisible() throws {
        let system = root.appendingPathComponent("system"), data = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try file("system-only", bytes: 11, at: system)
        let shared = try file("Users/shared", bytes: 17, at: system)
        try FileManager.default.createDirectory(at: data.appendingPathComponent("Users"), withIntermediateDirectories: true)
        XCTAssertEqual(link(shared.path, data.appendingPathComponent("Users/shared").path), 0)
        try file("private-data", bytes: 13, at: data)
        let systemRoot = try VolumeScanRoot(url: system, volumeUUID: "fixture-system", role: .system)
        let dataRoot = try VolumeScanRoot(url: data, volumeUUID: "fixture-data", role: .data)
        let target = try VolumeScanTarget(id: "fixture-group", name: "Generated Mac", roots: [systemRoot, dataRoot], displayRoot: system)
        let index = try ScanIndex(url: database)
        let scanner = VolumeScanner(home: root, volumeIdentifier: { $0.path == system.path ? "fixture-system" : "fixture-data" })
        let report = try scanner.scan(target, index: index, policy: unlimited)
        XCTAssertFalse(report.isPartial); XCTAssertEqual(report.root.logicalBytes, 41); XCTAssertEqual(report.root.fileCount, 3)
        XCTAssertEqual(try index.page(sessionID: report.id, search: "Users/shared").total, 1)
        let displayed = try XCTUnwrap(try index.page(sessionID: report.id, search: "private-data").items.first)
        XCTAssertTrue(displayed.path.contains(VolumeScanner.otherData))
        let sharedItem = try XCTUnwrap(try index.page(sessionID: report.id, search: "Users/shared").items.first)
        let location = try XCTUnwrap(try index.sourceLocation(sessionID: report.id, path: sharedItem.path))
        XCTAssertEqual(location.url.path, shared.path)
        XCTAssertTrue(["fixture-system", "fixture-data"].contains(location.volumeUUID))
    }
    func testDiscoveryGroupingUsesGroupIdentityRatherThanVolumeNameAndSamplesNeedNoTools() throws {
        let data = root.appendingPathComponent("data"); try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let uuid = IndexStoragePolicy.volumeIdentifier(source)
        let sample = VolumeInfo(uuid: uuid, name: "Generated", path: source.path, totalBytes: 1000, freeBytes: 900, isInternal: false, isWritable: true)
        var calls = 0
        let targets = Volumes.scanTargets(volumes: [sample], systemRoot: source, dataRoot: data, metadata: { _ in calls += 1; return nil })
        XCTAssertEqual(targets.count, 1); XCTAssertEqual(targets[0].roots[0].url.path, source.path); XCTAssertFalse(targets[0].isSystemGroup)
        XCTAssertEqual(calls, 2)
        let grouped = Volumes.scanTargets(volumes: [sample], systemRoot: source, dataRoot: data, metadata: { _ in VolumeDiscoveryMetadata(groupID: "generated-group") }, volumeIdentifier: { $0.path == self.source.path ? "generated-system" : "generated-data" })
        XCTAssertEqual(grouped.filter(\.isSystemGroup).count, 1)
        XCTAssertEqual(grouped.first(where: \.isSystemGroup)?.roots.count, 2)
    }
    func testIndexLocationSelectionIsExplicitAndExternalRequiresAPFSAndIdentity() throws {
        let uuid = IndexStoragePolicy.volumeIdentifier(source)
        let volume = VolumeInfo(uuid: uuid, name: "Generated external", path: source.path, totalBytes: 1000, freeBytes: 900, isInternal: false, isWritable: true)
        let internalChoice = try IndexStoragePolicy.location(internalDirectory: root, installationID: "generated", targetID: "target")
        XCTAssertEqual(internalChoice.policy, .internalStorage); XCTAssertNotEqual(internalChoice.url.lastPathComponent, "index.sqlite")
        XCTAssertThrowsError(try IndexStoragePolicy.location(internalDirectory: root, externalVolume: volume, installationID: "generated", targetID: "target", filesystemType: { _ in "exfat" }))
        XCTAssertThrowsError(try IndexStoragePolicy.location(internalDirectory: root, externalVolume: volume, installationID: "generated", targetID: "target", filesystemType: { _ in "apfs" }, volumeIdentifier: { _ in "different" }))
        let external = try IndexStoragePolicy.location(internalDirectory: root, externalVolume: volume, installationID: "generated", targetID: "target", filesystemType: { _ in "apfs" })
        XCTAssertEqual(external.policy, .externalSSD); XCTAssertTrue(Paths.contains(external.url, in: source)); XCTAssertNil(external.policy.maximumBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: external.url.path), "Choosing storage does not migrate or create an index")
        XCTAssertThrowsError(try IndexStoragePolicy.location(internalDirectory: root, externalVolume: volume, installationID: "generated", targetID: "target", filesystemType: { _ in "apfs" }, freeBytes: { _ in 0 }))
    }
    func testExternalIndexChoiceRejectsAnExistingRedirectedPrivateParent() throws {
        let outside = root.appendingPathComponent("unselected"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("MacCaches"), withDestinationURL: outside)
        let volume = VolumeInfo(uuid: IndexStoragePolicy.volumeIdentifier(source), name: "Generated", path: source.path, totalBytes: 1000, freeBytes: 900, isInternal: false, isWritable: true)
        XCTAssertThrowsError(try IndexStoragePolicy.location(internalDirectory: root, externalVolume: volume, installationID: "generated", targetID: "target", filesystemType: { _ in "apfs" }))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
    func testResumeRejectsReplacementRootAndDifferentVolumeIdentity() throws {
        for n in 0..<50 { try file("file-\(n)") }
        let index = try ScanIndex(url: database)
        let partial = try VolumeScanner(home: root, maximumEntriesPerPass: 12).scan(target(), index: index, policy: unlimited)
        let selected = try XCTUnwrap(try index.page(sessionID: partial.id, filesOnly: true).items.first)
        XCTAssertThrowsError(try VolumeScanner(home: root, volumeIdentifier: { _ in "different-volume" }).scan(target(), index: index, resumeSessionID: partial.id, policy: unlimited))
        let retained = root.appendingPathComponent("retained-source")
        try FileManager.default.moveItem(at: source, to: retained)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        XCTAssertNil(try index.sourceLocation(sessionID: partial.id, path: selected.path))
        XCTAssertThrowsError(try VolumeScanner(home: root).scan(target(), index: index, resumeSessionID: partial.id, policy: unlimited))
        XCTAssertEqual(try index.session(id: partial.id)?.state, "paused")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: retained.path).count, 50)
    }
    func testResumeReconcilesUnicodeDirectoryNamesWithoutLeavingOldDescendants() throws {
        let folder = "Cafe\u{301}-\u{1F9D1}\u{200D}\u{1F4BB}"
        for n in 0..<70 { try file(folder + "/old-\(n)", bytes: 1) }
        let index = try ScanIndex(url: database)
        let partial = try VolumeScanner(home: root, maximumEntriesPerPass: 20).scan(target(), index: index, policy: unlimited)
        try FileManager.default.removeItem(at: source.appendingPathComponent(folder))
        try file(folder + "/new", bytes: 29)
        let report = try VolumeScanner(home: root).scan(target(), index: index, resumeSessionID: partial.id, policy: unlimited)
        XCTAssertFalse(report.isPartial); XCTAssertEqual(report.root.logicalBytes, 29); XCTAssertEqual(report.root.fileCount, 1)
        XCTAssertEqual(try index.page(sessionID: report.id, search: "old-").total, 0)
    }
    func testQueuedDirectoryReplacedByLinkCannotTraverseAnUnselectedSibling() throws {
        try file("queued/inside", bytes: 11)
        for n in 0..<120 { try file("ordinary-\(n)", bytes: 1) }
        let outside = root.appendingPathComponent("unselected")
        try file("must-never-appear", bytes: 37, at: outside)
        let index = try ScanIndex(url: database), queued = source.appendingPathComponent("queued")
        var changed = false
        let report = try VolumeScanner(home: root).scan(target(), index: index, policy: unlimited, progress: { _ in
            if !changed {
                changed = true
                try! FileManager.default.moveItem(at: queued, to: self.root.appendingPathComponent("held-queue"))
                try! FileManager.default.createSymbolicLink(at: queued, withDestinationURL: outside)
            }
        })
        XCTAssertTrue(changed); XCTAssertTrue(report.isPartial)
        XCTAssertTrue(try index.page(sessionID: report.id, search: "must-never-appear").items.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), ["must-never-appear"])
    }
    func testFutureVolumeMetadataIsPreservedAndCannotResume() throws {
        try file("generated")
        let index = try ScanIndex(url: database)
        let partial = try VolumeScanner(home: root, maximumEntriesPerPass: 0).scan(target(), index: index, policy: unlimited)
        var value = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(target())) as? [String: Any])
        value["schemaVersion"] = 999
        let future = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
        try index.execute("UPDATE volume_targets SET target=? WHERE session=?", [.text(future), .text(partial.id.uuidString)])
        XCTAssertThrowsError(try VolumeScanner(home: root).scan(target(), index: index, resumeSessionID: partial.id, policy: unlimited))
        XCTAssertEqual(ScanIndex.string(try XCTUnwrap(index.execute("SELECT target FROM volume_targets WHERE session=?", [.text(partial.id.uuidString)]).first), "target"), future)
    }
}
