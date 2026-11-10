import XCTest
import Darwin
@testable import CacheSSDCore

/// Explicit opt-in; all bytes are generated and actually written on the fixture volume.
final class LargeFileQualificationTests: XCTestCase {
    func testFourGiBWrittenCopyAndCancellationPreserveSource() throws {
        guard ProcessInfo.processInfo.environment["DISKWING_RUN_LARGE_COPY_TESTS"] == "1" else { throw XCTSkip("Opt in to the generated 4 GiB written-copy qualification") }
        let parent = Paths.physicalURL(URL(fileURLWithPath:try XCTUnwrap(ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"])))
        let size: Int64 = 4_294_967_296
        guard Volumes.free(at:parent) > 12_884_901_888 else { throw CacheSSDError.message("The written-copy fixture needs at least 12 GiB free on its explicitly selected test volume.") }
        let root = parent.appendingPathComponent("DiskWing-written-copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:root) }
        let source = root.appendingPathComponent("generated.bin"), target = root.appendingPathComponent("verified.bin"), partial = root.appendingPathComponent("cancelled.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath:source.path,contents:nil,attributes:[.posixPermissions:0o600]))
        let file = try FileHandle(forWritingTo:source)
        var block = Data(count:1_048_576)
        block.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!,$0.count) }
        for _ in 0..<4096 { try file.write(contentsOf:block) }
        try file.synchronize(); try file.close()
        let measurement = FileTree.measure(source)
        XCTAssertEqual(measurement.logical,size)
        XCTAssertGreaterThanOrEqual(measurement.allocated,size,"Fixture must not be sparse")
        let expected = try FileTree.digest(source,workspace:root), cancellation = CancellationFlag(), start = Date()
        XCTAssertThrowsError(try FileTree.copyItem(source,to:partial,cancellation:cancellation,progress:{ _ in cancellation.cancel() }))
        XCTAssertTrue(cancellation.isCancelled)
        XCTAssertLessThan(Date().timeIntervalSince(start),10)
        XCTAssertGreaterThan(FileTree.measure(partial).logical,0)
        XCTAssertLessThan(FileTree.measure(partial).logical,size)
        let copyStart = Date()
        try FileTree.copyItem(source,to:target)
        let copySeconds = Date().timeIntervalSince(copyStart)
        XCTAssertEqual(try FileTree.digest(target,workspace:root),expected)
        XCTAssertEqual(try FileTree.digest(source,workspace:root),expected)
        XCTAssertEqual(FileTree.measure(target).logical,size)
        var usage = rusage(); XCTAssertEqual(getrusage(RUSAGE_SELF,&usage),0)
        XCTAssertLessThan(usage.ru_maxrss,268_435_456)
        if let output = ProcessInfo.processInfo.environment["DISKWING_LARGE_COPY_REPORT"] {
            let report: [String:Any] = ["schemaVersion":1,"date":ISO8601DateFormatter().string(from:Date()),"logicalBytes":size,"sourceAllocatedBytes":measurement.allocated,"copySeconds":copySeconds,"peakResidentBytes":usage.ru_maxrss,"copyVerified":true,"sourcePreserved":true,"cancellationVerified":true,"scope":"Generated same-volume data; no sparse source, physical unplug or internal user files"]
            let destination = URL(fileURLWithPath:output)
            let data = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
            let fd = open(destination.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
            guard fd >= 0 else { throw CacheSSDError.message("Choose a new private qualification report filename.") }
            let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true); try handle.write(contentsOf:data); try handle.synchronize(); try handle.close()
        }
    }
}
