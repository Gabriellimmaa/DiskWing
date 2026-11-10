import XCTest
@testable import CacheSSDCore

final class PersistenceCompatibilityTests: XCTestCase {
    func testFutureCompletedRecordsArePreservedAndConfigurationRemainsPending() throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        let root = Paths.physicalURL(base).appendingPathComponent("DiskWing-future-record-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = Store(base:root.appendingPathComponent("support")), source = root.appendingPathComponent("sample")
        try Data("keep".utf8).write(to:source)
        let context = try OperationContext(store:store,kind:"trash",source:source)
        try context.advance(.completed)
        let filename = "operation-\(context.journal.id.uuidString).json", path = store.base.appendingPathComponent(filename)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any]); object["schemaVersion"] = 2
        let original = try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]); try original.write(to:path)
        try store.pruneCompletedOperations(keeping:0)
        try store.append(OperationRecord(title:"fixture",detail:"fixture"))
        XCTAssertEqual(try Data(contentsOf:path),original)
        var configuration = ConfigurationChange(source:source.path,before:"before",after:"after"); configuration.state = "completed"
        try store.write(configuration,name:"configuration-future.json")
        let configPath = store.base.appendingPathComponent("configuration-future.json")
        var config = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:configPath)) as? [String:Any]); config["schemaVersion"] = 2
        let configBytes = try JSONSerialization.data(withJSONObject:config,options:[.sortedKeys]); try configBytes.write(to:configPath)
        XCTAssertTrue(store.pendingConfigurationRecords().contains("configuration-future.json"))
        XCTAssertEqual(try Data(contentsOf:configPath),configBytes)
        XCTAssertEqual(try Data(contentsOf:source),Data("keep".utf8))
    }
}
