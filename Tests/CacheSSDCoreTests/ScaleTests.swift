import XCTest
import Darwin
@testable import CacheSSDCore

final class ScaleTests: XCTestCase {
    func testOneMillionRealEntriesRemainQueryableWithBoundedMemory() throws {
        guard ProcessInfo.processInfo.environment["DISKWING_RUN_SCALE_TESTS"] == "1" else { throw XCTSkip("Opt in to the disposable one-million-entry filesystem benchmark") }
        let base = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"]))
        let fixture = base.appendingPathComponent("DiskWing-scale-\(UUID().uuidString)")
        let tree = fixture.appendingPathComponent("tree")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        for folder in 0..<999 {
          try autoreleasepool {
            let directory = tree.appendingPathComponent(String(format: "d%03d",folder))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            for file in 0..<1000 {
                let path = directory.appendingPathComponent(String(format:"f%04d",file))
                let fd = open(path.path,O_CREAT|O_WRONLY|O_EXCL,0o600)
                guard fd >= 0 else { throw CacheSSDError.message("Scale fixture creation failed") }; close(fd)
            }
        }
          }
        let index = try ScanIndex(url: fixture.appendingPathComponent("store/index.sqlite"))
        let start = Date()
        let report = try IndexedScanner().scan(tree,index:index)
        let duration = Date().timeIntervalSince(start)
        XCTAssertFalse(report.isPartial)
        XCTAssertEqual(report.examinedEntries,1_000_000)
        XCTAssertEqual(try index.page(sessionID:report.id,search:"d998/f0999").total,1)
        XCTAssertEqual(try index.page(sessionID:report.id,filesOnly:true,offset:998_900).items.count,100)
        var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
        XCTAssertLessThan(usage.ru_maxrss, 536_870_912)
        if let destination = ProcessInfo.processInfo.environment["DISKWING_SCALE_REPORT"] {
            let value: [String:Any] = ["entries":report.examinedEntries,"partial":report.isPartial,"scanSeconds":duration,"indexBytes":index.byteSize(),"peakResidentBytes":usage.ru_maxrss,"architecture":"arm64","date":ISO8601DateFormatter().string(from:Date())]
            try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:destination))
        }
    }
}
