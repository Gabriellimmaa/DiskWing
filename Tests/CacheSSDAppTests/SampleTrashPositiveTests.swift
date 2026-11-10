import XCTest
import Foundation
@testable import CacheSSDApp
import CacheSSDCore

@MainActor final class SampleTrashPositiveTests: XCTestCase {
    private func verifyMove(internalStorage: Bool, physicalSource: Bool) throws {
        let fm = FileManager.default
        let parent: URL
        if internalStorage { parent = fm.temporaryDirectory }
        else {
            parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? fm.temporaryDirectory
        }
        let workspace = Paths.physicalURL(parent).appendingPathComponent(".DiskWing-trash-positive-\(UUID().uuidString)")
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace); L10n.preference = "system" }
        let context = try AppContext.makeSamples(workspace: workspace), session = try XCTUnwrap(context.container)
        let ordinary = context.home.appendingPathComponent("Downloads/nested/find-me.txt")
        let source = physicalSource ? Paths.physicalURL(ordinary) : ordinary.standardizedFileURL
        let expected = try Data(contentsOf: source)
        let outside = workspace.appendingPathComponent("sibling-sentinel.txt")
        try Data("preserved sibling".utf8).write(to: outside)
        let destination = session.appendingPathComponent("personal-destination")
        let record = try context.personalActions().move(source, to: destination)
        XCTAssertFalse(fm.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(source.lastPathComponent)), expected)
        XCTAssertEqual(record.recoveryPath, destination.appendingPathComponent(source.lastPathComponent).path)
        let trash = URL(fileURLWithPath: try XCTUnwrap(context.store.operations().first?.trashPath))
        XCTAssertTrue(Paths.contains(trash, in: session.appendingPathComponent("sample-trash")))
        XCTAssertEqual(try Data(contentsOf: trash), expected)
        XCTAssertEqual(try String(contentsOf: outside), "preserved sibling")
        XCTAssertEqual(context.store.operations().first?.phase, .completed)
    }
    func testGeneratedMoveOnExternalFixtureUsesPrivateTrash() async throws {
        try verifyMove(internalStorage: false, physicalSource: true)
    }
    func testGeneratedMoveFromInternalPhysicalPathUsesPrivateTrash() async throws {
        try verifyMove(internalStorage: true, physicalSource: true)
    }
    func testGeneratedMoveFromInternalStandardizedAliasUsesPrivateTrash() async throws {
        try verifyMove(internalStorage: true, physicalSource: false)
    }
}
