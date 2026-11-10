import XCTest
@testable import CacheSSDCore

final class UpdatePolicyTests: XCTestCase {
    var root: URL!
    var store: Store!
    override func setUpWithError() throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(base).appendingPathComponent("DiskWing-update-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = Store(base: root.appendingPathComponent("support"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func testAutomaticChecksNeedConsentButManualChecksRemainAvailable() {
        let idle = UpdateSafetyState()
        XCTAssertFalse(UpdatePolicy.canCheck(automatic: true, consent: false, state: idle))
        XCTAssertTrue(UpdatePolicy.canCheck(automatic: true, consent: true, state: idle))
        XCTAssertTrue(UpdatePolicy.canCheck(automatic: false, consent: false, state: idle))
        XCTAssertFalse(UpdatePolicy.automaticDownloads); XCTAssertFalse(UpdatePolicy.systemProfiling)
    }
    func testEverySafetyBlockerPreventsCheckAndInstallation() {
        for state in [UpdateSafetyState(workInProgress: true), UpdateSafetyState(pendingRecovery: true),
                      UpdateSafetyState(unreadableRecords: true), UpdateSafetyState(pendingConfiguration: true)] {
            XCTAssertFalse(UpdatePolicy.canCheck(automatic: false, consent: true, state: state))
            XCTAssertFalse(UpdatePolicy.canCheck(automatic: true, consent: true, state: state))
            XCTAssertFalse(UpdatePolicy.canInstall(state: state))
        }
    }
    func testUpdateSessionExcludesOtherMutationsUntilItIsReleased() throws {
        var session: UpdateSessionLease? = try UpdateSessionLease(store: store, isBusy: { false })
        XCTAssertThrowsError(try OperationLease(store: store))
        try session?.revalidate(); session = nil
        let lease = try OperationLease(store: store); withExtendedLifetime(lease) {}
    }
    func testFailedPreflightReleasesLeaseAndPreservesPendingRecord() throws {
        let source = root.appendingPathComponent("sample"); try Data("keep".utf8).write(to: source)
        let operation = try OperationContext(store: store, kind: "trash", source: source)
        XCTAssertThrowsError(try UpdateSessionLease(store: store, isBusy: { false }))
        XCTAssertEqual(try Data(contentsOf: source), Data("keep".utf8))
        XCTAssertEqual(store.operations().first?.id, operation.journal.id)
        let lease = try OperationLease(store: store); withExtendedLifetime(lease) {}
    }
    func testSessionRevalidatesBusyAndNewPendingRecoveryBeforeRelaunch() throws {
        var busy = false
        let session = try UpdateSessionLease(store: store, isBusy: { busy })
        busy = true; XCTAssertThrowsError(try session.revalidate()); busy = false
        let source = root.appendingPathComponent("sample"); try Data("keep".utf8).write(to: source)
        let operation = try OperationContext(store: store, kind: "trash", source: source)
        XCTAssertThrowsError(try session.revalidate())
        try operation.advance(.completed)
        try session.revalidate()
    }
    func testUnreadableAndConfigurationRecordsCannotMasqueradeAsIdle() throws {
        try FileManager.default.createDirectory(at: store.base, withIntermediateDirectories: true)
        let invalid = store.base.appendingPathComponent("operation-unreadable.json")
        try Data("invalid".utf8).write(to: invalid)
        XCTAssertThrowsError(try UpdateSessionLease(store: store, isBusy: { false }))
        XCTAssertEqual(try String(contentsOf: invalid), "invalid")
        try FileManager.default.removeItem(at: invalid)
        let name = "configuration-fixture.json"
        var change = ConfigurationChange(source: "generated", before: "before", after: "after")
        try store.writeDurably(change, name: name)
        XCTAssertThrowsError(try UpdateSessionLease(store: store, isBusy: { false }))
        change.state = "completed"; try store.writeDurably(change, name: name)
        let session = try UpdateSessionLease(store: store, isBusy: { false }); try session.revalidate()
    }
}
