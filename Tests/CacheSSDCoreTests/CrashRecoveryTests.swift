import XCTest
import Darwin
@testable import CacheSSDCore

final class CrashRecoveryTests: XCTestCase {
    func testCrashWorker() throws {
        guard let path = ProcessInfo.processInfo.environment["DISKWING_CRASH_FIXTURE"],
              let point = ProcessInfo.processInfo.environment["DISKWING_CRASH_POINT"] else { throw XCTSkip("Subprocess-only disposable crash worker") }
        let root = URL(fileURLWithPath:path), home = root.appendingPathComponent("home")
        let store = Store(base:root.appendingPathComponent("store"))
        let actions = PersonalActions(home:home,store:store,trashHandler:{ source in
            try FileManager.default.moveItem(at:source,to:root.appendingPathComponent("private-trash"))
            if point == "afterTrash" { _exit(86) }
            return root.appendingPathComponent("private-trash")
        },checkpoint:{ journal in if point == "published" && journal.phase == .published { _exit(86) } })
        _ = try actions.move(home.appendingPathComponent("Downloads/item.txt"),to:root.appendingPathComponent("destination"))
        XCTFail("Crash boundary was not reached")
    }
    func testAbruptProcessExitKeepsVerifiedCopyAndRecoversMissingOriginal() throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        for point in ["published","afterTrash"] {
            let root = Paths.physicalURL(base).appendingPathComponent("DiskWing-crash-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at:root) }
            let home = root.appendingPathComponent("home"), source = home.appendingPathComponent("Downloads/item.txt")
            try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
            try FileManager.default.createDirectory(at:root.appendingPathComponent("destination"),withIntermediateDirectories:true)
            try Data("verified original".utf8).write(to:source)
            var env = ProcessInfo.processInfo.environment
            env["DISKWING_CRASH_FIXTURE"] = root.path; env["DISKWING_CRASH_POINT"] = point
            let result = try CommandRunner.run(URL(fileURLWithPath:"/usr/bin/xcrun"),["xctest","-XCTest","CacheSSDCoreTests.CrashRecoveryTests/testCrashWorker",Bundle(for:Self.self).bundleURL.path],environment:env,timeout:30)
            XCTAssertEqual(result.status,86,result.output)
            let store = Store(base:root.appendingPathComponent("store")), recovery = RecoveryManager(store:store,home:Paths.physicalURL(home))
            let journal = try XCTUnwrap(store.operations().first)
            XCTAssertTrue(journal.isPending)
            XCTAssertEqual(try String(contentsOf:root.appendingPathComponent("destination/item.txt")),"verified original")
            if point == "afterTrash" {
                XCTAssertFalse(FileManager.default.fileExists(atPath:source.path))
                try recovery.restoreSource(id:journal.id)
            }
            XCTAssertEqual(try String(contentsOf:source),"verified original")
        }
    }
}
