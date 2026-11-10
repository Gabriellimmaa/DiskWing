import XCTest
import Darwin
@testable import CacheSSDCore

final class AcceptanceTests: XCTestCase {
    var root: URL!
    let helper = URL(fileURLWithPath: "/usr/bin/true")
    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-acceptance-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func reportBytes(_ report: AcceptanceReport) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return try encoder.encode(report)
    }
    func testPortableFlowPreservesExistingFilesAndReportsNoPersonalPaths() throws {
        let sentinel = root.appendingPathComponent("existing.txt"), bytes = Data("untouched user fixture".utf8)
        try bytes.write(to: sentinel)
        let previous = L10n.preference; L10n.preference = "en"; defer { L10n.preference = previous }
        let report = try AcceptanceRunner.run(workspace: root, helper: helper)
        XCTAssertTrue(report.passed); XCTAssertEqual(report.checks.map(\.id), AcceptanceRunner.checkIDs)
        XCTAssertEqual(report.pendingManualGates, AcceptanceRunner.manualGates)
        XCTAssertEqual(report.helperSHA256, try FileTree.hash(helper))
        XCTAssertEqual(L10n.preference, "en")
        XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["existing.txt"])
        let text = String(decoding: try reportBytes(report), as: UTF8.self)
        for secret in [root.path, NSUserName(), FileManager.default.homeDirectoryForCurrentUser.path, "GENERATED-ACCEPTANCE-VOLUME", "installationID"] { XCTAssertFalse(text.contains(secret), secret) }
    }
    func testFailureRetainsOnlyGeneratedFixturesAndStopsRemainingChecks() throws {
        let report = try AcceptanceRunner.run(workspace: root, helper: helper, beforeCheck: { id in
            if id == "personal-copy-recovery" { throw CacheSSDError.message("private-path-should-not-escape") }
        })
        XCTAssertFalse(report.passed); XCTAssertEqual(report.fixtureDisposition, "retained-for-review")
        XCTAssertEqual(report.checks.map(\.status), ["passed", "passed", "failed", "not-run", "not-run"])
        XCTAssertFalse(String(decoding: try reportBytes(report), as: UTF8.self).contains("private-path-should-not-escape"))
        let fixtures = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(fixtures.count, 1)
        XCTAssertTrue(fixtures[0].lastPathComponent.hasPrefix(".DiskWing-acceptance-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtures[0].appendingPathComponent("home/Downloads/sample/nested/sample.txt").path))
        var info = stat(); XCTAssertEqual(lstat(fixtures[0].path, &info), 0); XCTAssertEqual(info.st_mode & 0o077, 0)
    }
    func testMissingFileAndLinkedWorkspacesAreRejectedBeforeCreatingFixtures() throws {
        let missing = root.appendingPathComponent("missing"), file = root.appendingPathComponent("file"), link = root.appendingPathComponent("link")
        try Data("keep".utf8).write(to: file)
        let target = root.appendingPathComponent("target"); try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        for workspace in [missing, file, link] { XCTAssertThrowsError(try AcceptanceRunner.run(workspace: workspace, helper: helper)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(try String(contentsOf: file), "keep")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }
    func testMissingHelperLeavesWorkspaceUntouched() throws {
        XCTAssertThrowsError(try AcceptanceRunner.run(workspace: root, helper: root.appendingPathComponent("missing-helper")))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testSystemTemporaryDirectoryAliasesRemainUsable() throws {
        // Foundation may shorten /private/var; realpath keeps the physical spelling.
        let directory = Paths.physicalURL(FileManager.default.temporaryDirectory).appendingPathComponent("DiskWing-alias-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = try AcceptanceRunner.run(workspace: directory, helper: helper, beforeCheck: { _ in }, onFailure: { id, error in XCTFail("\(id): \(error)") })
        XCTAssertTrue(report.passed)
        let output = directory.appendingPathComponent("report.json").standardizedFileURL
        try report.write(to: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }
    func testReportIsPrivateAndNeverOverwritesExistingFileOrLink() throws {
        let report = try AcceptanceRunner.run(workspace: root, helper: helper)
        let output = root.appendingPathComponent("report.json")
        try report.write(to: output)
        let original = try Data(contentsOf: output)
        XCTAssertThrowsError(try report.write(to: output))
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: output)
        XCTAssertThrowsError(try report.write(to: link))
        XCTAssertEqual(try Data(contentsOf: output), original)
        var info = stat(); XCTAssertEqual(lstat(output.path, &info), 0); XCTAssertEqual(info.st_mode & 0o777, 0o600)
        XCTAssertEqual(try JSONDecoder.acceptance.decode(AcceptanceReport.self, from: original).pendingManualGates, AcceptanceRunner.manualGates)
    }
}
private extension JSONDecoder {
    static var acceptance: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}
