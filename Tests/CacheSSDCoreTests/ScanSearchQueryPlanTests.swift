import XCTest
import Foundation
@testable import CacheSSDCore

/// Compare page() with the previous unforced SQL contract. EXPLAIN independently
/// verifies table-scan plans on the generated schema, without production hooks.
final class ScanSearchQueryPlanTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var index: ScanIndex!
    private var sessionID: UUID!

    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-query-plan-" + UUID().uuidString)
        source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let database = root.appendingPathComponent("state/index.sqlite")
        index = try ScanIndex(url: database)
        sessionID = try seed(source: source)
        _ = try seed(source: root.appendingPathComponent("other-session"))
    }
    override func tearDownWithError() throws {
        index = nil
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func seed(source: URL) throws -> UUID {
        let id = UUID()
        try index.begin(root: source, id: id, volume: "GENERATED", started: Date())
        let entries: [(String, Int64, Int64, Bool, Bool)] = [
            ("", 0, 0, true, false),
            ("Café/Report.txt", 100, 800, false, false),
            ("cafe/report.txt", 100, 900, false, false),
            ("misc/CAFÉ-100%_final.txt", 90, 110, false, false),
            ("misc/cafe-100XYfinal.txt", 90, 12, false, false),
            ("misc/CAFÉ\\draft.txt", 70, 99, false, false),
            ("misc/zero-café.txt", 0, 4096, false, false),
            ("misc/folder-café", 200, 100, true, false),
            ("misc/link-café", 150, 100, false, true),
            ("ties/a-cafe.txt", 30, 40, false, false),
            ("ties/A-cafe.txt", 30, 40, false, false),
            ("ties/z-cafe.txt", 30, 30, false, false),
            ("tail/unique-needle-Vídeo.txt", 1, 4096, false, false)
        ]
        for entry in entries { try add(entry, id: id, source: source) }
        for number in 0..<512 {
            let name = String(format: "bulk/entry-%04d.txt", number)
            try add((name, Int64(number + 1000), Int64(9000 - number), false, false), id: id, source: source)
        }
        try index.execute("UPDATE sessions SET state='complete' WHERE id=?", [.text(id.uuidString)])
        try index.execute("COMMIT")
        return id
    }
    private func add(_ value: (String, Int64, Int64, Bool, Bool), id: UUID, source: URL) throws {
        let path = value.0.isEmpty ? source : source.appendingPathComponent(value.0)
        let item = ScanItem(path: path.path, name: path.lastPathComponent, isDirectory: value.3, isSymbolicLink: value.4,
                            logicalBytes: value.1, allocatedBytes: value.2, fileCount: value.3 ? 0 : 1,
                            category: .personal, issue: nil, children: [])
        try index.add(id: id, relative: value.0, item: item, depth: value.0.split(separator: "/").count)
    }
    private func page(parent: String? = nil, search: String, filesOnly: Bool = false, minimum: Int64 = 0,
                      allocated: Bool = false, offset: Int = 0, limit: Int = 120) throws -> (IndexedPage, [String]) {
        let result = try index.page(sessionID: sessionID, parent: parent, search: search, filesOnly: filesOnly,
                                    minimumBytes: minimum, allocatedOrder: allocated, offset: offset, limit: limit)
        let statements = try baselineStatements(parent: parent, search: search, filesOnly: filesOnly,
            minimum: minimum, allocated: allocated, offset: offset, limit: limit)
        return (result, statements)
    }
    private func baselineStatements(parent: String?, search: String, filesOnly: Bool, minimum: Int64,
                                    allocated: Bool, offset: Int, limit: Int) throws -> [String] {
        // This is the pre-optimization contract, intentionally without a table
        // constraint. Values are quoted by SQLite, not interpolated as raw SQL.
        func quote(_ value: String) throws -> String {
            ScanIndex.string(try index.execute("SELECT quote(?) AS value", [.text(value)]).first ?? [:], "value")
        }
        var filters = ["session=" + (try quote(sessionID.uuidString)), "path<>''"]
        if let parent {
            let relative = parent == source.path ? "" : String(parent.dropFirst(source.path.count + 1))
            filters.append("parent=" + (try quote(relative)))
        }
        if !search.isEmpty {
            let folded = search.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
            filters.append("searchable LIKE " + (try quote("%" + folded + "%")) + " ESCAPE '\\'")
        }
        if filesOnly { filters.append("directory=0 AND link=0") }
        filters.append("logical>=" + String(max(0, minimum)))
        let predicate = filters.joined(separator: " AND ")
        let order = allocated ? "allocated" : "logical"
        let count = "SELECT COUNT(*) AS count FROM entries WHERE " + predicate
        let rows = "SELECT * FROM entries WHERE " + predicate + " ORDER BY " + order + " DESC,name COLLATE NOCASE,path LIMIT " + String(max(1, min(500, limit))) + " OFFSET " + String(max(0, offset))
        return [count, rows]
    }
    private func compareWithPrevious(_ result: IndexedPage, statements: [String]) throws {
        let legacy = statements
        let count = try XCTUnwrap(legacy.first { $0.hasPrefix("SELECT COUNT") })
        let select = try XCTUnwrap(legacy.first { $0.hasPrefix("SELECT *") })
        let expectedTotal = ScanIndex.integer(try index.execute(count).first ?? [:], "count")
        let expected = try index.execute(select)
        XCTAssertEqual(result.total, Int(expectedTotal))
        XCTAssertEqual(result.items.map(\.path), expected.map { source.appendingPathComponent(ScanIndex.string($0, "path")).path })
        XCTAssertEqual(result.items.map(\.logicalBytes), expected.map { ScanIndex.integer($0, "logical") })
        XCTAssertEqual(result.items.map(\.allocatedBytes), expected.map { ScanIndex.integer($0, "allocated") })
        XCTAssertEqual(result.items.map(\.isDirectory), expected.map { ScanIndex.integer($0, "directory") == 1 })
        XCTAssertEqual(result.items.map(\.isSymbolicLink), expected.map { ScanIndex.integer($0, "link") == 1 })
        XCTAssertLessThanOrEqual(result.items.count, result.limit)
        XCTAssertEqual(result.hasNext, result.offset + result.items.count < result.total)
    }
    private func plan(_ sql: String) throws -> [String] {
        try index.execute("EXPLAIN QUERY PLAN " + sql).map { ScanIndex.string($0, "detail") }
    }

    func testRareAndCommonGlobalSearchesHaveSequentialCountAndBoundedPagePlans() throws {
        for search in ["entry", "unique-needle", "CAFÉ", "100%_", "\\draft", "not present"] {
            for allocated in [false, true] {
                let (result, statements) = try page(search: search, allocated: allocated, limit: 7)
                try compareWithPrevious(result, statements: statements)
                for baseline in statements {
                    let statement = baseline.replacingOccurrences(of: "FROM entries WHERE", with: "FROM entries NOT INDEXED WHERE")
                    let details = try plan(statement)
                    XCTAssertTrue(details.contains { $0.hasPrefix("SCAN entries") }, details.joined(separator: "; "))
                    XCTAssertFalse(details.contains { $0.contains("USING INDEX") || $0.contains("USING COVERING INDEX") })
                }
            }
        }
    }
    func testUnicodeWildcardsFilesOnlyAndPaginationKeepPreviousResultsAcrossSessions() throws {
        for minimum: Int64 in [-1, 0, 1, 100, Int64.max] {
            for filesOnly in [false, true] {
                for allocated in [false, true] {
                    for offset in [-4, 0, 3, 1000] {
                        let (result, statements) = try page(search: "café", filesOnly: filesOnly, minimum: minimum,
                                                            allocated: allocated, offset: offset, limit: 3)
                        try compareWithPrevious(result, statements: statements)
                        XCTAssertEqual(result.offset, max(0, offset)); XCTAssertEqual(result.limit, 3)
                        XCTAssertTrue(result.items.allSatisfy { $0.path.hasPrefix(source.path + "/") })
                    }
                }
            }
        }
        XCTAssertEqual(try page(search: "100%_").0.items.map(\.name), ["CAFÉ-100%_final.txt"])
        XCTAssertEqual(try page(search: "\\draft").0.items.map(\.name), ["CAFÉ\\draft.txt"])
        XCTAssertEqual(try page(search: "VIDEO").0.items.map(\.name), ["unique-needle-Vídeo.txt"])
        XCTAssertEqual(try page(search: "cafe").0.total, 11)
        XCTAssertEqual(try page(search: "cafe", filesOnly: true).0.total, 9)
        XCTAssertEqual(try page(search: "cafe", filesOnly: true, minimum: 100).0.total, 2)
        XCTAssertEqual(try page(search: "ties/").0.items.map(\.name), ["A-cafe.txt", "a-cafe.txt", "z-cafe.txt"])
        XCTAssertEqual(try page(search: "entry", limit: 10_000).0.items.count, 500)
        XCTAssertEqual(try page(search: "entry", limit: 0).0.items.count, 1)
        XCTAssertEqual(try page(search: "entry").0.total, 512, "The other session has the same paths and must not contribute")
        XCTAssertNotEqual(try page(search: "cafe", allocated: false).0.items.map(\.path), try page(search: "cafe", allocated: true).0.items.map(\.path))
    }
    func testNonGlobalQueriesKeepPreviousResultsAndCoveringCountBaseline() throws {
        for query in [(nil as String?, "", Int64(0)), (source.path as String?, "café", Int64(0)), (nil, "café", Int64(1))] {
            let (result, statements) = try page(parent: query.0, search: query.1, minimum: query.2)
            try compareWithPrevious(result, statements: statements)
        }
        let (_, statements) = try page(search: "")
        let count = try XCTUnwrap(statements.first { $0.hasPrefix("SELECT COUNT") })
        XCTAssertTrue(try plan(count).contains { $0.contains("USING COVERING INDEX") }, "Do not replace the cheap unfiltered covering-index COUNT")
    }
}
