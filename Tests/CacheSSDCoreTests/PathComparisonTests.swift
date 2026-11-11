import XCTest
@testable import CacheSSDCore

final class PathComparisonTests: XCTestCase {
    func testMissingLeafDirectoryHintsAndDotComponentsKeepLexicalContainment() throws {
        let root = Paths.physicalURL(FileManager.default.temporaryDirectory).appendingPathComponent("DiskWing-paths-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for hint in [true, false] {
            XCTAssertTrue(Paths.contains(URL(fileURLWithPath: root.path + "/missing", isDirectory: hint), in: root))
            XCTAssertFalse(Paths.contains(URL(fileURLWithPath: root.path + "/../sibling", isDirectory: hint), in: root))
        }
        XCTAssertTrue(Paths.contains(root.appendingPathComponent("nested/../inside"), in: root))
        XCTAssertFalse(Paths.contains(URL(string: "https://example.test" + root.path)!, in: root))
    }
    func testCustomSymlinkIsNotExpandedByTheComparisonContract() throws {
        let root = Paths.physicalURL(FileManager.default.temporaryDirectory).appendingPathComponent("DiskWing-path-links-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("real"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("custom")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root.appendingPathComponent("real"))
        XCTAssertTrue(Paths.comparisonPath(alias).hasSuffix("/custom"))
        XCTAssertFalse(Paths.contains(alias.appendingPathComponent("child"), in: root.appendingPathComponent("real")))
    }
}
