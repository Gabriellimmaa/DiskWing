import XCTest
import Foundation
@testable import CacheSSDApp
import CacheSSDCore

@MainActor final class SampleTrashIsolationTests: XCTestCase {
    func testRedirectedSampleTrashPreservesSourceAndSibling() async throws {
        let (root, context) = try AppAcceptanceTests().fixture()
        defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let session = try XCTUnwrap(context.container), fm = FileManager.default
        let outside = root.appendingPathComponent("sibling-fixture")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("sentinel")
        try Data("preserved sibling".utf8).write(to: sentinel)
        let source = context.home.appendingPathComponent("Downloads/sample-001.txt")
        let before = try FileTree.digest(source), siblingBefore = try FileTree.digest(outside)
        try fm.createSymbolicLink(at: session.appendingPathComponent("sample-trash"), withDestinationURL: outside)
        XCTAssertThrowsError(try context.personalActions().trash(source))
        XCTAssertEqual(try FileTree.digest(source), before)
        XCTAssertEqual(try FileTree.digest(outside), siblingBefore)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: outside.path), ["sentinel"])
    }
}
