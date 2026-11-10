import XCTest
@testable import CacheSSDCore

final class PreflightTests: XCTestCase {
    var root: URL!
    var home: URL!
    var source: URL!
    override func setUpWithError() throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(base).appendingPathComponent("DiskWing-preflight-\(UUID().uuidString)")
        home = root.appendingPathComponent("home"); source = home.appendingPathComponent("Downloads/generated")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for n in 0..<450 { try Data([42]).write(to: source.appendingPathComponent("file-\(n)")) }
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func testMeasurementLimitAndCancellationNeverLookCompleteOrChangeData() throws {
        let before = try FileTree.digest(source, workspace: root)
        let limited = FileTree.measure(source, maxEntries: 64)
        XCTAssertTrue(limited.reachedLimit); XCTAssertFalse(limited.isComplete); XCTAssertEqual(limited.entries, 64)
        let token = CancellationFlag()
        let cancelled = FileTree.measure(source, cancellation: token, progress: { _ in token.cancel() })
        XCTAssertTrue(cancelled.isCancelled); XCTAssertFalse(cancelled.isComplete)
        XCTAssertGreaterThan(cancelled.entries, 0); XCTAssertLessThan(cancelled.entries, 450)
        let complete = FileTree.measure(source, maxEntries: 450)
        XCTAssertTrue(complete.isComplete); XCTAssertEqual(complete.entries, 450); XCTAssertEqual(complete.logical, 450)
        XCTAssertEqual(try FileTree.digest(source, workspace: root), before)
    }
    func testCancelledOrLimitedPolicyStopsBeforeAnyOperationRecord() throws {
        let store = Store(base: root.appendingPathComponent("support")), token = CancellationFlag()
        XCTAssertThrowsError(try PersonalActionPolicy.validateTree(source, home: home, cancellation: token, maxEntries: 64))
        XCTAssertThrowsError(try PersonalActionPolicy.validateTree(source, home: home, cancellation: token, progress: { _ in token.cancel() }))
        XCTAssertTrue(token.isCancelled)
        let destination = root.appendingPathComponent("destination"); try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let actions = PersonalActions(home: home, store: store, trashHandler: { _ in XCTFail("No Trash call during preflight"); return nil })
        XCTAssertThrowsError(try actions.move(source, to: destination, cancellation: token))
        XCTAssertTrue(store.operations().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: source.path).count, 450)
    }
    func testFolderChildChangedAtTrashBoundaryPreservesBothVersionsWithoutTrash() throws {
        let store = Store(base: root.appendingPathComponent("support")), destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let child = source.appendingPathComponent("file-0")
        var inspected = 0, trashCheckpoints = 0
        let actions = PersonalActions(home: home, store: store, trashHandler: { _ in XCTFail("Changed folder must not be trashed"); return nil }, busyCheck: { paths, tool in
            XCTAssertEqual(paths.map(\.path), [self.source.path]); XCTAssertNil(tool)
            inspected += 1; return []
        }, checkpoint: { journal in
            if journal.phase == .trashing { trashCheckpoints += 1; try Data("new local data".utf8).write(to: child) }
        })
        XCTAssertThrowsError(try actions.move(source, to: destination))
        XCTAssertEqual(trashCheckpoints, 1, "The intended Trash boundary must be reached")
        XCTAssertEqual(inspected, 3)
        XCTAssertEqual(try String(contentsOf: child), "new local data")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(source.lastPathComponent).appendingPathComponent("file-0")), Data([42]))
        XCTAssertEqual(store.operations().first?.phase, .interrupted)
    }
}
