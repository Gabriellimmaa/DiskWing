import XCTest
import Foundation
@testable import CacheSSDApp
import CacheSSDCore

@MainActor final class UpdateBridgeTests: XCTestCase {
    func testGUIUpdateLeaseBlocksMutationAndReleasesOnNewRecoveryState() async throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        let root = Paths.physicalURL(base).appendingPathComponent("DiskWing-update-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(base: root.appendingPathComponent("support")), updates = Updates(store: store)
        updates.operationInProgress = { false }
        try updates.requireIdle()
        XCTAssertThrowsError(try OperationLease(store: store))
        let source = root.appendingPathComponent("fixture"); try Data("generated".utf8).write(to: source)
        let record = try OperationJournal(kind: "personalMove", source: source)
        try store.writeDurably(record, name: "operation-\(record.id.uuidString).json")
        XCTAssertThrowsError(try updates.requireIdle())
        // A rejected update must not keep the lease that recovery needs.
        let lease = try OperationLease(store: store); withExtendedLifetime(lease) {}
    }
    func testDisabledSampleUpdaterCannotAcquireASession() async throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        let root = Paths.physicalURL(base).appendingPathComponent("DiskWing-update-disabled-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let updates = Updates(store: Store(base: root.appendingPathComponent("support")), disabled: true)
        updates.operationInProgress = { false }
        XCTAssertFalse(updates.available)
        XCTAssertThrowsError(try updates.requireIdle())
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("support").path))
    }
    func testStartupFailureReleasesLeaseAndAllowsRetry() async throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        let root = Paths.physicalURL(base).appendingPathComponent("DiskWing-update-startup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(base: root.appendingPathComponent("support")), updates = Updates(store: store)
        updates.operationInProgress = { false }
        try updates.requireIdle()
        XCTAssertThrowsError(try updates.start(using: { throw CacheSSDError.message("injected startup failure") }))
        XCTAssertFalse(updates.started)
        do { let lease = try OperationLease(store: store); withExtendedLifetime(lease) {} }
        var starts = 0
        try updates.start(using: { starts += 1 })
        XCTAssertTrue(updates.started); XCTAssertEqual(starts, 1)
        try updates.start(using: { XCTFail("An already started updater must not restart") })
    }
    func testDisabledSamplesNeverInvokeInjectedStartup() async throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        let root = Paths.physicalURL(base).appendingPathComponent("DiskWing-update-no-start-\(UUID().uuidString)")
        let updates = Updates(store: Store(base: root), disabled: true)
        XCTAssertThrowsError(try updates.start(using: { XCTFail("Samples must not initialize an updater driver") }))
        XCTAssertFalse(updates.started); XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
