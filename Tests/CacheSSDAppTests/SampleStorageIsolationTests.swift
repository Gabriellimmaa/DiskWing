import XCTest
import Foundation
@testable import CacheSSDApp
import CacheSSDCore

@MainActor final class SampleStorageIsolationTests: XCTestCase {
    func testRecordsRedirectedAfterLaunchAreRefusedBeforeConvenienceReads() async throws {
        let (root, context) = try AppAcceptanceTests().fixture()
        defer { try? FileManager.default.removeItem(at: root); L10n.preference = "system" }
        let model = AppModel(context: context), fm = FileManager.default
        let outside = root.appendingPathComponent("sibling-record.json")
        let sentinel = Data("private sibling fixture".utf8); try sentinel.write(to: outside)
        for name in ["history.json", "preferences.json", "migration-generated.json"] {
            let path = context.store.base.appendingPathComponent(name)
            let backup = context.store.base.appendingPathComponent("preserved-" + name)
            if fm.fileExists(atPath: path.path) { try fm.moveItem(at: path, to: backup) }
            try fm.createSymbolicLink(at: path, withDestinationURL: outside)
            XCTAssertThrowsError(try context.requireStorage())
            model.reloadRecords(); XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(try Data(contentsOf: outside), sentinel)
            try fm.removeItem(at: path)
            if fm.fileExists(atPath: backup.path) { try fm.moveItem(at: backup, to: path) }
        }
        XCTAssertNoThrow(try context.requireStorage())
    }
}
