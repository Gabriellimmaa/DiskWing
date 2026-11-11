import XCTest
import Darwin
@testable import CacheSSDCore

final class VolumeScanScaleTests: XCTestCase {
    func testMoreThanOneMillionEntriesUseDurableVolumeScannerAndResumeChangedDirectory() throws {
        guard ProcessInfo.processInfo.environment["DISKWING_RUN_VOLUME_SCALE_TESTS"] == "1" else { throw XCTSkip("Opt in to the new volume scanner's generated >1M-entry filesystem qualification") }
        let parent = Paths.physicalURL(URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"])))
        guard Volumes.free(at: parent) >= 8_589_934_592 else { throw CacheSSDError.message("The generated volume qualification requires at least 8 GiB free fixture space") }
        let fixture = parent.appendingPathComponent("DiskWing-volume-scale-\(UUID().uuidString)")
        let tree = fixture.appendingPathComponent("tree")
        let fixtureStarted = Date()
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        for folder in 0..<1001 {
            try autoreleasepool {
                let directory = tree.appendingPathComponent(String(format: "group%04d", folder))
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard descriptor >= 0 else { throw CacheSSDError.message("Could not prepare the generated volume fixture") }
                defer { close(descriptor) }
                for file in 0..<1000 {
                    let output = openat(descriptor, String(format: "file%04d", file), O_CREAT | O_WRONLY | O_EXCL | O_CLOEXEC, 0o600)
                    guard output >= 0 else { throw CacheSSDError.message("Could not create the generated volume fixture") }
                    close(output)
                }
            }
        }
        try Data(repeating: 17, count: 17).write(to: tree.appendingPathComponent("group0000/file0000"))
        let selected = try VolumeScanTarget.folder(tree, name: "Generated volume scale fixture")
        let storageVolume = VolumeInfo(uuid: IndexStoragePolicy.volumeIdentifier(fixture), name: "Generated index storage", path: fixture.path, totalBytes: 0, freeBytes: Volumes.free(at: fixture), isInternal: false, isWritable: true)
        let storage = try IndexStoragePolicy.location(internalDirectory: fixture.appendingPathComponent("support"), externalVolume: storageVolume, installationID: "generated-volume-scale", targetID: selected.id)
        let index = try storage.openIndex()
        defer { try? index.close() }
        let started = Date()
        let paused = try VolumeScanner(home: fixture, maximumEntriesPerPass: 600_000).scan(selected, index: index, policy: storage.policy)
        XCTAssertTrue(paused.isPartial)
        XCTAssertEqual(try index.resumableVolumeSession(targetID: selected.id), paused.id)
        try Data(repeating: 35, count: 35).write(to: tree.appendingPathComponent("group0000/post-pause-added"))
        let report = try VolumeScanner(home: fixture).scan(selected, index: index, resumeSessionID: paused.id, policy: storage.policy)
        XCTAssertFalse(report.isPartial)
        XCTAssertGreaterThan(report.examinedEntries, 1_000_000)
        XCTAssertEqual(report.root.fileCount, 1_001_001)
        XCTAssertEqual(report.root.logicalBytes, 52)
        let searchMatches = try index.page(sessionID: report.id, search: "group1000/file0999").total
        let changedDirectoryMatches = try index.page(sessionID: report.id, search: "post-pause-added").total
        XCTAssertEqual(searchMatches, 1)
        XCTAssertEqual(changedDirectoryMatches, 1)
        let last = try index.page(sessionID: report.id, parent: tree.appendingPathComponent("group1000").path, allocatedOrder: true, offset: 999, limit: 128)
        XCTAssertEqual(last.total, 1000); XCTAssertEqual(last.items.count, 1); XCTAssertFalse(last.hasNext)
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        XCTAssertLessThan(usage.ru_maxrss, 536_870_912)
        if let output = ProcessInfo.processInfo.environment["DISKWING_VOLUME_SCALE_REPORT"] {
            let value: [String: Any] = ["scanner": "VolumeScanner", "storage": "bound-openIndex-externalSSD", "entries": report.examinedEntries, "files": report.root.fileCount, "logicalBytes": report.root.logicalBytes, "allocatedBytes": report.root.allocatedBytes, "partial": report.isPartial, "pausedEntries": paused.examinedEntries, "resumedChangedDirectory": true, "globalSearchMatches": searchMatches, "changedDirectorySearchMatches": changedDirectoryMatches, "lastPageTotal": last.total, "lastPageItems": last.items.count, "lastPageHasNext": last.hasNext, "seconds": Date().timeIntervalSince(started), "fixtureAndScanSeconds": Date().timeIntervalSince(fixtureStarted), "indexBytes": index.byteSize(), "peakResidentBytes": usage.ru_maxrss]
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output), options: .withoutOverwriting)
        }
    }
}
