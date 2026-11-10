import XCTest
import Foundation
import Darwin
@testable import CacheSSDApp
import CacheSSDCore

private final class LaunchPreparationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@MainActor final class LaunchCoordinatorTests: XCTestCase {
    private func fixture() throws -> URL {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        let root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-launch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func wait(until condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), "Launch did not finish")
    }
    func testConstructionDefersFilesystemWorkUntilApplicationFinishedLaunching() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let launch = LaunchCoordinator(arguments: ["DiskWing", "--acceptance-workspace", root.path], bundleIdentifier: "com.cachessd.app.acceptance")
        XCTAssertNil(launch.model); XCTAssertTrue(launch.isLoading)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        launch.start()
        try await wait(until: { !launch.isLoading })
        XCTAssertNil(launch.failureMessage); XCTAssertTrue(try XCTUnwrap(launch.model).context.isSamples)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(names.count, 1)
        launch.start()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), names)
    }
    func testPreparationRunsOffMainActorWhileLoadingRemainsResponsive() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let proceed = DispatchSemaphore(value: 0), probe = LaunchPreparationProbe()
        let launch = LaunchCoordinator(arguments: ["DiskWing", "--acceptance-workspace", root.path], bundleIdentifier: "com.cachessd.app.acceptance") { request in
            _ = probe.next(); XCTAssertFalse(Thread.isMainThread)
            guard proceed.wait(timeout: .now() + 5) == .success, case .create(let workspace) = request else { throw SampleWorkspace.failure() }
            return try SampleWorkspace.prepare(workspace: workspace)
        }
        launch.start(); launch.start()
        try await wait(until: { probe.calls == 1 })
        XCTAssertTrue(launch.isLoading); XCTAssertNil(launch.model); XCTAssertEqual(probe.calls, 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        proceed.signal()
        try await wait(until: { !launch.isLoading })
        XCTAssertNil(launch.failureMessage); XCTAssertTrue(try XCTUnwrap(launch.model).context.isSamples)
    }
    func testInvalidAcceptanceRequestsNeverPrepareOrCreateLiveModel() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let probe = LaunchPreparationProbe()
        let requests: [([String], String)] = [
            (["DiskWing"], "com.cachessd.app.acceptance"),
            (["DiskWing", "--acceptance-workspace"], "com.cachessd.app.acceptance"),
            (["DiskWing", "--acceptance-unknown", root.path], "com.cachessd.app.acceptance"),
            (["DiskWing", "--acceptance-workspace", root.path, "--acceptance-session", root.path], "com.cachessd.app.acceptance"),
            (["DiskWing", "--acceptance-workspace", root.path], "com.cachessd.app")
        ]
        for (arguments, identifier) in requests {
            let launch = LaunchCoordinator(arguments: arguments, bundleIdentifier: identifier) { _ in _ = probe.next(); throw SampleWorkspace.failure() }
            launch.start(); try await wait(until: { !launch.isLoading })
            XCTAssertNil(launch.model); XCTAssertNotNil(launch.failureMessage)
        }
        XCTAssertEqual(probe.calls, 0); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testWorkerFailureCanRetryWithoutLiveFallback() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let probe = LaunchPreparationProbe()
        let launch = LaunchCoordinator(arguments: ["DiskWing", "--acceptance-workspace", root.path], bundleIdentifier: "com.cachessd.app.acceptance") { request in
            guard probe.next() > 1, case .create(let workspace) = request else { throw SampleWorkspace.failure() }
            return try SampleWorkspace.prepare(workspace: workspace)
        }
        launch.start(); try await wait(until: { !launch.isLoading })
        XCTAssertNil(launch.model); XCTAssertNotNil(launch.failureMessage)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        launch.start(); try await wait(until: { !launch.isLoading })
        XCTAssertEqual(probe.calls, 2); XCTAssertNil(launch.failureMessage)
        XCTAssertTrue(try XCTUnwrap(launch.model).context.isSamples)
    }
    func testInvalidPersistentSessionStaysUntouchedAndDoesNotOpenLiveData() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let prepared = try SampleWorkspace.prepare(workspace: root), marker = prepared.root.appendingPathComponent(".diskwing-sample-session")
        let unknown = Data("future-unknown-marker\n".utf8); try unknown.write(to: marker)
        let launch = LaunchCoordinator(arguments: ["DiskWing", "--acceptance-session", prepared.root.path], bundleIdentifier: "com.cachessd.app.acceptance")
        launch.start(); try await wait(until: { !launch.isLoading })
        XCTAssertNil(launch.model); XCTAssertNotNil(launch.failureMessage)
        XCTAssertEqual(try Data(contentsOf: marker), unknown)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
    }
    func testSessionIdentityIsRevalidatedAfterWorkerPreparation() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let prepared = try SampleWorkspace.prepare(workspace: root)
        try FileManager.default.moveItem(at: prepared.root, to: root.appendingPathComponent("preserved-session"))
        try FileManager.default.createDirectory(at: prepared.root, withIntermediateDirectories: false)
        XCTAssertThrowsError(try AppContext.preparedSamples(prepared))
    }
    func testResumeRefusesFIFOAndOversizedConfigurationBeforeReadingIt() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let prepared = try SampleWorkspace.prepare(workspace: root), settings = prepared.support.appendingPathComponent("settings.json")
        try FileManager.default.removeItem(at: settings)
        XCTAssertEqual(mkfifo(settings.path, 0o600), 0)
        let started = Date()
        XCTAssertThrowsError(try SampleWorkspace.validate(session: prepared.root))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        try FileManager.default.removeItem(at: settings)
        try Data(repeating: 32, count: 8_388_609).write(to: settings)
        XCTAssertThrowsError(try SampleWorkspace.validate(session: prepared.root))
    }
    func testResumeMetadataPreflightRejectsDatalessAndSpecialFilesWithoutReadingContent() {
        var metadata = stat(); metadata.st_mode = S_IFREG | 0o600
        XCTAssertTrue(SampleWorkspace.validSupportEntry(metadata))
        metadata.st_flags = UInt32(SF_DATALESS)
        XCTAssertFalse(SampleWorkspace.validSupportEntry(metadata))
        metadata.st_flags = 0
        for kind in [S_IFIFO, S_IFSOCK, S_IFLNK, S_IFCHR] {
            metadata.st_mode = kind | 0o600
            XCTAssertFalse(SampleWorkspace.validSupportEntry(metadata))
        }
    }
}
