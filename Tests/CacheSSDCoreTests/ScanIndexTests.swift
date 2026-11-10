import XCTest
import Foundation
@testable import CacheSSDCore

final class ScanIndexTests: XCTestCase {
    var root: URL!
    var source: URL!
    var index: ScanIndex!
    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = parent.appendingPathComponent("DiskWing-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = Paths.physicalURL(root); source = root.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        index = try ScanIndex(url: root.appendingPathComponent("state/index.sqlite"))
    }
    override func tearDownWithError() throws { index = nil; try? FileManager.default.removeItem(at: root) }
    @discardableResult func file(_ name: String, bytes: Int = 10) throws -> URL {
        let path = source.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 65, count: bytes).write(to: path); return path
    }
    func testPaginationAndSearchRetainItemsBeyondOldDisplayLimit() throws {
        for number in 0..<320 { try file("entry-\(number).txt", bytes: number + 1) }
        let report = try IndexedScanner().scan(source, index: index)
        let first = try index.page(sessionID: report.id, parent: source.path, limit: 120)
        let last = try index.page(sessionID: report.id, parent: source.path, offset: 240, limit: 120)
        XCTAssertEqual(first.total, 320); XCTAssertEqual(first.items.count, 120)
        XCTAssertEqual(last.items.count, 80); XCTAssertFalse(last.hasNext)
        let smallest = try index.page(sessionID: report.id, search: "entry-0.txt")
        XCTAssertEqual(smallest.items.map(\.name), ["entry-0.txt"])
        XCTAssertEqual(report.root.logicalBytes, Int64((1...320).reduce(0,+)))
    }
    func testSearchIsGlobalUnicodeAwareAndTreatsSQLWildcardsLiterally() throws {
        try file("nested/deeper/Vídeo-100%_final.txt")
        try file("nested/deeper/Video-100XYfinal.txt")
        let report = try IndexedScanner().scan(source, index: index)
        let page = try index.page(sessionID: report.id, search: "VIDEO-100%_")
        XCTAssertEqual(page.total, 1); XCTAssertEqual(page.items.first?.name, "Vídeo-100%_final.txt")
        XCTAssertEqual(try index.page(sessionID: report.id, search: "nested/deeper").total, 3)
    }
    func testDirectoryTotalsHardLinksAndExternalLinksMatchScope() throws {
        let original = try file("nested/data", bytes: 8192)
        try FileManager.default.linkItem(at: original, to: source.appendingPathComponent("alias"))
        let external = root.appendingPathComponent("external"); try Data(repeating: 2, count: 9999).write(to: external)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("external-link"), withDestinationURL: external)
        let report = try IndexedScanner().scan(source, index: index)
        XCTAssertEqual(report.root.logicalBytes, 16384)
        XCTAssertEqual(report.root.fileCount, 2)
        let folder = try XCTUnwrap(try index.page(sessionID: report.id, parent: source.path).items.first { $0.name == "nested" })
        XCTAssertEqual(folder.logicalBytes, 8192)
        XCTAssertEqual(try index.page(sessionID: report.id, filesOnly: true).total, 2)
    }
    func testLimitAndCancellationPersistPartialSessions() throws {
        for number in 0..<15 { try file("entry\(number)") }
        let report = try IndexedScanner(maxEntries: 6).scan(source, index: index)
        XCTAssertTrue(report.isPartial); XCTAssertEqual(report.examinedEntries, 6)
        XCTAssertEqual(try index.session(id: report.id)?.state, "partial")
        let token = CancellationFlag(); token.cancel()
        let cancelled = try IndexedScanner().scan(source, index: index, cancellation: token)
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertEqual(try index.session(id: cancelled.id)?.state, "cancelled")
    }
    func testFullExportIncludesEveryIndexedEntryAndCanBeReadAfterReopen() throws {
        for number in 0..<255 { try file("entry\(number)") }
        let report = try IndexedScanner().scan(source, index: index)
        let output = root.appendingPathComponent("export.json")
        try index.export(sessionID: report.id, to: output)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        XCTAssertEqual((document["entries"] as? [[String: Any]])?.count, 255)
        XCTAssertEqual(document["schemaVersion"] as? Int, 2)
        index = nil
        let reopened = try ScanIndex(url: root.appendingPathComponent("state/index.sqlite"))
        XCTAssertEqual(try reopened.page(sessionID: report.id, parent: source.path).total, 255)
    }
    func testRetentionRemovesOlderTreesWithoutLosingCurrentResults() throws {
        try file("one")
        for _ in 0..<3 { _ = try IndexedScanner().scan(source, index: index) }
        XCTAssertEqual(try index.sessions().count, 2)
        let current = try XCTUnwrap(try index.sessions().first)
        XCTAssertEqual(try index.page(sessionID: current.id).total, 1)
    }
    func testScopeRejectsUnrelatedParentAndRootContainmentIsCorrect() throws {
        try file("one")
        let report = try IndexedScanner().scan(source, index: index)
        XCTAssertThrowsError(try index.page(sessionID: report.id, parent: root.path))
        XCTAssertTrue(Paths.contains(URL(fileURLWithPath: "/Users/example"), in: URL(fileURLWithPath: "/")))
    }

    func testIdentityPersistsAndCancelledExportPreservesExistingReport() throws {
        let path = try file("retained.txt"), identity = try FileIdentity(path)
        let report = try IndexedScanner().scan(source, index: index)
        XCTAssertEqual(try index.page(sessionID: report.id, search: "retained").items.first?.fileIdentity, identity)
        let output = root.appendingPathComponent("report.json")
        try Data("previous report".utf8).write(to: output)
        let token = CancellationFlag(); token.cancel()
        XCTAssertThrowsError(try index.export(sessionID: report.id, to: output, cancellation: token))
        XCTAssertEqual(try String(contentsOf: output), "previous report")
        let linked = root.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: output)
        XCTAssertThrowsError(try index.export(sessionID: report.id, to: linked))
        XCTAssertThrowsError(try index.export(sessionID: report.id, to: index.url))
        XCTAssertEqual(try String(contentsOf: output), "previous report")
    }
    func testOwnIndexIsExcludedAndFutureSchemaIsPreserved() throws {
        try file("visible",bytes: 19)
        let nested = try ScanIndex(url: source.appendingPathComponent("private-index/index.sqlite"))
        let report = try IndexedScanner().scan(source, index: nested)
        XCTAssertEqual(report.root.logicalBytes,19)
        XCTAssertEqual(report.root.fileCount,1)
        try nested.execute("PRAGMA user_version=99")
        XCTAssertThrowsError(try ScanIndex(url: nested.url))
        XCTAssertEqual(ScanIndex.integer(try nested.execute("PRAGMA user_version").first ?? [:], "user_version"),99)
    }
}
