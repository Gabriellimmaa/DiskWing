import XCTest
import Darwin
@testable import CacheSSDCore

final class CopyScaleTests: XCTestCase {
    func testLargeTreeVerificationAndCopyRemainBounded() throws {
        guard ProcessInfo.processInfo.environment["DISKWING_RUN_COPY_SCALE_TESTS"] == "1" else { throw XCTSkip("Opt in to disposable copy/verification resource qualification") }
        let base = URL(fileURLWithPath:try XCTUnwrap(ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"]))
        let root = Paths.physicalURL(base).appendingPathComponent("DiskWing-copy-scale-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("verified-copy")
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        for folder in 0..<200 {
            try autoreleasepool {
                let directory = source.appendingPathComponent(String(format:"d%03d",folder))
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                for file in 0..<100 { try Data("fixture-data".utf8).write(to:directory.appendingPathComponent(String(format:"f%03d",file))) }
            }
        }
        let large = source.appendingPathComponent("large.bin")
        let fd = open(large.path,O_CREAT|O_WRONLY|O_EXCL,0o600)
        guard fd >= 0 else { throw CacheSSDError.message("Scale fixture failed") }
        let resized = ftruncate(fd,67_108_864); close(fd); XCTAssertEqual(resized,0)
        let start = Date(), measured = FileTree.measure(source)
        XCTAssertTrue(measured.isComplete)
        let expected = try FileTree.digest(source,workspace:root)
        try FileTree.copy(source,to:target)
        XCTAssertEqual(try FileTree.digest(target,workspace:root),expected)
        XCTAssertEqual(try FileTree.digest(source,workspace:root),expected)
        XCTAssertEqual(FileTree.measure(target).logical,measured.logical)
        var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
        XCTAssertLessThan(usage.ru_maxrss,268_435_456)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:root.path).filter { $0.hasPrefix(".DiskWing-verification-") }.isEmpty)
        if let path = ProcessInfo.processInfo.environment["DISKWING_COPY_SCALE_REPORT"] {
            let values: [String:Any] = ["files":20_001,"directories":201,"logicalBytes":measured.logical,"seconds":Date().timeIntervalSince(start),"peakResidentBytes":usage.ru_maxrss,"digestCompatibility":"legacy sorted JSON","originalPreserved":true,"copyVerified":true,"scope":"Same-volume generated fixture; filesystem-image cases run separately","date":ISO8601DateFormatter().string(from:Date())]
            try JSONSerialization.data(withJSONObject:values,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
        }
    }
}
