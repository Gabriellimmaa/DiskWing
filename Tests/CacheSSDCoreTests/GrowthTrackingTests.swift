import XCTest
import Foundation
@testable import CacheSSDCore

final class GrowthTrackingTests: XCTestCase {
    var root: URL!
    var source: URL!
    var index: ScanIndex!
    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = parent.appendingPathComponent("DiskWing-growth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); root = Paths.physicalURL(root)
        source = root.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("folder"), withIntermediateDirectories: true)
        index = try ScanIndex(url: root.appendingPathComponent("state/index.sqlite"))
    }
    override func tearDownWithError() throws { index = nil; try? FileManager.default.removeItem(at: root) }
    func snapshot(bytes: Int, limit: Int = 1000) throws -> ScanReport {
        try Data(repeating: 1, count: bytes).write(to: source.appendingPathComponent("folder/item"))
        return try IndexedScanner(maxEntries: limit).scan(source, index: index)
    }
    func testGrowthComparesSameScopeAndFolderTotals() throws {
        _ = try snapshot(bytes: 10); _ = try snapshot(bytes: 60)
        let comparison = try index.growth(root: source.path)
        XCTAssertEqual(comparison.state, "comparable")
        XCTAssertEqual(comparison.logicalDelta, 50)
        XCTAssertEqual(comparison.folders.first?.logicalDelta, 50)
        XCTAssertTrue(comparison.folderCoverageComplete)
    }
    func testMissingFolderIsUnavailableRatherThanReclaimedSpace() throws {
        _ = try snapshot(bytes: 10); _ = try snapshot(bytes: 60)
        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("removed"))
        let comparison = try index.growth(root: source.path)
        XCTAssertEqual(comparison.state, "unavailable"); XCTAssertNil(comparison.logicalDelta)
    }
    func testPartialLatestScanCannotClaimGrowth() throws {
        _ = try snapshot(bytes: 10); _ = try snapshot(bytes: 60, limit: 2)
        let comparison = try index.growth(root: source.path)
        XCTAssertEqual(comparison.state, "unavailable"); XCTAssertNil(comparison.logicalDelta)
    }
    func testSevenDayComparisonRequiresAnOldEnoughBaseline() throws {
        let first = try snapshot(bytes: 10); _ = try snapshot(bytes: 60)
        XCTAssertEqual(try index.growth(root: source.path, days: 7).state, "unavailable")
        try index.execute("UPDATE snapshots SET time=? WHERE id=?", [.real(Date().addingTimeInterval(-8*86400).timeIntervalSince1970),.text(first.id.uuidString)])
        XCTAssertEqual(try index.growth(root: source.path, days: 7).logicalDelta, 50)
    }
    func testDifferentVolumeCannotBeCompared() throws {
        let first = try snapshot(bytes: 10); _ = try snapshot(bytes: 60)
        try index.execute("UPDATE snapshots SET volume='DIFFERENT-VOLUME' WHERE id=?", [.text(first.id.uuidString)])
        XCTAssertEqual(try index.growth(root: source.path).state, "unavailable")
    }
    func testAdvisoryEventsDetectDisposableFileChanges() throws {
        let observed = expectation(description: "filesystem event")
        let lock = NSLock(); var done = false
        let monitor = try DirectoryEventMonitor(root: source) { _ in
            lock.lock(); defer { lock.unlock() }
            if !done { done = true; observed.fulfill() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now()+0.3) { try? Data("changed".utf8).write(to: self.source.appendingPathComponent("event")) }
        wait(for: [observed], timeout: 15)
        withExtendedLifetime(monitor) {}
    }
}
