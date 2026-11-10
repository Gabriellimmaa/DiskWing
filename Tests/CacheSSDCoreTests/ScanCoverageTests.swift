import XCTest
import Foundation
@testable import CacheSSDCore

final class ScanCoverageTests: XCTestCase {
    var root: URL!
    var source: URL!
    var index: ScanIndex!
    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.processInfoEnvironmentFixture
        root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-coverage-\(UUID().uuidString)")
        source = root.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        index = try ScanIndex(url: root.appendingPathComponent("state/index.sqlite"))
    }
    override func tearDownWithError() throws { index = nil; try? FileManager.default.removeItem(at: root) }
    func testRepeatedScansFitBudgetForTwoRetainedTrees() throws {
        for number in 0..<2200 { try Data().write(to: source.appendingPathComponent(String(format:"entry-%05d-fixture.txt", number))) }
        for _ in 0..<2 { XCTAssertFalse(try IndexedScanner().scan(source, index: index).isPartial) }
        let budget = index.byteSize() + 131_072
        for _ in 0..<4 {
            let report = try IndexedScanner(maxIndexBytes: budget).scan(source, index: index)
            XCTAssertFalse(report.isPartial, "Repeated scan was limited although two trees fit; budget \(budget), used \(index.byteSize())")
            XCTAssertEqual(report.examinedEntries, 2201)
            XCTAssertEqual(try index.page(sessionID: report.id).total, 2200)
        }
        XCTAssertEqual(try index.sessions().count, 2)
    }
    func testUnreadableDirectoryIsUnknownAndAncestorsArePartial() throws {
        let hidden = source.appendingPathComponent("hidden")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try Data("not enumerated".utf8).write(to: hidden.appendingPathComponent("file"))
        try Data("known".utf8).write(to: source.appendingPathComponent("visible"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: hidden.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hidden.path) }
        let report = try IndexedScanner().scan(source, index: index)
        XCTAssertTrue(report.isPartial); XCTAssertEqual(report.root.coverage, .partial)
        let row = try XCTUnwrap(try index.page(sessionID: report.id, parent: source.path).items.first { $0.name == "hidden" })
        XCTAssertEqual(row.coverage, .unknown); XCTAssertEqual(row.logicalBytes, 0)
        XCTAssertEqual(report.root.logicalBytes, 5)
        let output = root.appendingPathComponent("report.json"); try index.export(sessionID: report.id, to: output)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String:Any])
        let entries = try XCTUnwrap(document["entries"] as? [[String:Any]])
        XCTAssertEqual(entries.first { $0["name"] as? String == "hidden" }?["coverage"] as? String, "unknown")
        XCTAssertEqual(try index.session(id: report.id)?.state, "partial")
    }
    func testRealEmptyDirectoryIsCompleteAndPartialLimitStaysExplicit() throws {
        let report = try IndexedScanner().scan(source, index: index)
        XCTAssertFalse(report.isPartial); XCTAssertEqual(report.root.coverage, .complete); XCTAssertEqual(report.root.logicalBytes, 0)
        for number in 0..<8 { try Data().write(to: source.appendingPathComponent("file\(number)")) }
        let limited = try IndexedScanner(maxEntries: 3).scan(source, index: index)
        XCTAssertTrue(limited.isPartial); XCTAssertEqual(limited.root.coverage, .partial)
        let legacy = try DiskScanner(maxEntries: 3).scan(source)
        XCTAssertTrue(legacy.isPartial); XCTAssertEqual(legacy.root.coverage, .partial)
    }
    func testLegacyJSONAndUnknownCoverageDecodeConservatively() throws {
        let item = ScanItem(path: "/fixture", name: "fixture", isDirectory: true, isSymbolicLink: false, logicalBytes: 0, allocatedBytes: 0, fileCount: 0, category: .unknown, issue: "Sem acesso; tamanho desconhecido", children: [])
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String:Any])
        value.removeValue(forKey: "coverage")
        XCTAssertEqual(try JSONDecoder().decode(ScanItem.self, from: JSONSerialization.data(withJSONObject: value)).coverage, .unknown)
        value["issue"] = "Há conteúdo da nuvem ainda não baixado. A origem será preservada."
        XCTAssertEqual(try JSONDecoder().decode(ScanItem.self, from: JSONSerialization.data(withJSONObject: value)).coverage, .partial)
        value.removeValue(forKey: "issue"); value["coverage"] = "future-coverage"
        XCTAssertEqual(try JSONDecoder().decode(ScanItem.self, from: JSONSerialization.data(withJSONObject: value)).coverage, .unknown)
    }
    func testLegacyIndexCloudCoverageInvalidatesMisleadingHistory() throws {
        let id = UUID(), started = Date()
        try index.begin(root: source, id: id, volume: "fixture", started: started)
        let node = ScanItem(path: source.path, name: "files", isDirectory: true, isSymbolicLink: false, logicalBytes: 0, allocatedBytes: 0, fileCount: 0, category: .unknown, issue: nil, children: [])
        let cloud = ScanItem(path: source.appendingPathComponent("cloud").path, name: "cloud", isDirectory: false, isSymbolicLink: false, logicalBytes: 10, allocatedBytes: 0, fileCount: 1, category: .unknown, issue: "Há conteúdo da nuvem ainda não baixado. A origem será preservada.", children: [])
        try index.add(id: id, relative: "", item: node, depth: 0)
        try index.add(id: id, relative: "cloud", item: cloud, depth: 1)
        try index.finish(id: id, depth: 1, logical: 10, allocated: 0, files: 1, entries: 2, partial: false, cancelled: false)
        XCTAssertEqual(try index.session(id: id)?.state, "partial")
        // Model an old index that reported metadata-only cloud entries complete.
        try index.execute("UPDATE sessions SET state='complete'")
        try index.execute("UPDATE snapshots SET state='complete'")
        try index.execute("ALTER TABLE entries DROP COLUMN coverage")
        try index.execute("PRAGMA user_version=2")
        let path = index.url; index = nil; index = try ScanIndex(url: path)
        XCTAssertEqual(try index.session(id: id)?.state, "partial")
        XCTAssertEqual(try index.report(id: id).root.coverage, .partial)
        XCTAssertEqual(ScanIndex.string(try index.execute("SELECT state FROM snapshots WHERE id=?", [.text(id.uuidString)]).first ?? [:], "state"), "partial")
        XCTAssertEqual(try index.page(sessionID: id).items.first?.coverage, .partial)
    }

}
private extension ProcessInfo {
    var processInfoEnvironmentFixture: URL { environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory }
}
