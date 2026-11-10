import XCTest
import CryptoKit
import Darwin
@testable import CacheSSDCore

final class VerificationTests: XCTestCase {
    var root: URL!
    var source: URL!
    override func setUpWithError() throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(base).appendingPathComponent("DiskWing-verification-test-\(UUID().uuidString)")
        source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    @discardableResult func file(_ name: String, text: String = "sample") throws -> URL {
        let file = source.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file); return file
    }
    func sparseFile() throws -> URL {
        let file = try file("large.bin")
        let fd = open(file.path, O_WRONLY); guard fd >= 0 else { throw CacheSSDError.message("Fixture open failed") }
        defer { close(fd) }
        guard ftruncate(fd, 67_108_864) == 0 else { throw CacheSSDError.message("Fixture resize failed") }
        return file
    }
    func testStreamedDigestMatchesHistoricalJSONBytesAndUnicodeOrdering() throws {
        for path in ["z.txt", "é.txt", "e\u{301}x.txt", "😀.txt", "nested/quoted\"line\n.txt", "À.txt"] { try file(path) }
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "z.txt")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var oldBytes = Data(try FileTree.metadataDigest(source).utf8)
        oldBytes.append(try encoder.encode(FileTree.manifest(source)))
        let oldHash = SHA256.hash(data: oldBytes).map { String(format:"%02x",$0) }.joined()
        XCTAssertEqual(try FileTree.digest(source, workspace: root), oldHash)
    }
    func testEmptyDirectoryDigestMatchesHistoricalFormat() throws {
        let oldHash = SHA256.hash(data: Data((try FileTree.metadataDigest(source) + "[]").utf8)).map { String(format:"%02x",$0) }.joined()
        XCTAssertEqual(try FileTree.digest(source, workspace: root),oldHash)
    }
    func testLargeSingleFileCanCancelDuringTransfer() throws {
        let file = try sparseFile(), target = root.appendingPathComponent("partial.bin"), token = CancellationFlag()
        let expected = try FileTree.hash(file), start = Date()
        XCTAssertThrowsError(try FileTree.copyItem(file,to:target,cancellation:token,progress:{ _ in token.cancel() }))
        XCTAssertTrue(token.isCancelled)
        XCTAssertLessThan(Date().timeIntervalSince(start),10)
        XCTAssertEqual(try FileTree.hash(file),expected)
        let partial = FileTree.measure(target)
        XCTAssertGreaterThan(partial.logical,0); XCTAssertLessThan(partial.logical,67_108_864)
    }
    func testExistingFileIsNeverOverwrittenByStreamedCopy() throws {
        let file = try file("file"), target = root.appendingPathComponent("existing")
        try Data("keep".utf8).write(to:target)
        XCTAssertThrowsError(try FileTree.copyItem(file,to:target))
        XCTAssertEqual(try String(contentsOf:target),"keep")
    }
    func testSourceGrowthDuringTransferIsDetected() throws {
        let file = try sparseFile(), target = root.appendingPathComponent("changed.bin")
        var changed = false
        XCTAssertThrowsError(try FileTree.copyItem(file,to:target,progress:{ _ in
            guard !changed else { return }; changed = true
            do {
                let handle = try FileHandle(forWritingTo:file); defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf:Data([42]))
            } catch { XCTFail(error.localizedDescription) }
        }))
        XCTAssertTrue(changed)
        XCTAssertEqual(FileTree.measure(file).logical,67_108_865)
    }
    func testDirectoryMetadataIsAppliedBottomUpAndCopiesStayEquivalent() throws {
        try file("deep/nested/file")
        let folder = source.appendingPathComponent("deep")
        try FileManager.default.setAttributes([.posixPermissions:0o750,.modificationDate:Date(timeIntervalSince1970:1_500_000_000)],ofItemAtPath:folder.path)
        let target = root.appendingPathComponent("copy"), before = try FileTree.digest(source,workspace:root)
        try FileTree.copy(source,to:target)
        XCTAssertEqual(try FileTree.digest(target,workspace:root),before)
    }
    func testVerificationLimitsAndCleanupDoNotModifySource() throws {
        try file("keep")
        let original = try FileTree.digest(source,workspace:root)
        do {
            let store = try VerificationStore(workspace:root,maxEntries:1)
            try store.add(ManifestEntry(path:"first",kind:"file",size:0,digest:""))
            XCTAssertThrowsError(try store.add(ManifestEntry(path:"second",kind:"file",size:0,digest:"")))
        }
        do {
            let store = try VerificationStore(workspace:root,maxBytes:0)
            XCTAssertThrowsError(try store.forEach { _,_ in })
        }
        XCTAssertThrowsError(try VerificationStore(workspace:root,minimumFree:Int64.max))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:root.path).filter { $0.hasPrefix(".DiskWing-verification-") }.isEmpty)
        XCTAssertEqual(try FileTree.digest(source,workspace:root),original)
    }
    func testWorkspacesAndCopyTargetsCannotRecurseIntoSource() throws {
        try file("keep")
        XCTAssertThrowsError(try FileTree.digest(source,workspace:source))
        XCTAssertThrowsError(try FileTree.copy(source,to:source.appendingPathComponent("recursive")))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:source.path),["keep"])
    }
    func testVerificationWorkspaceAcceptsSystemTemporaryDirectoryAliases() throws {
        let directory = Paths.physicalURL(FileManager.default.temporaryDirectory).appendingPathComponent("DiskWing-digest-alias-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        try Data("generated".utf8).write(to: fixture.appendingPathComponent("file"))
        let alias = URL(fileURLWithPath: directory.path, isDirectory: true).standardizedFileURL
        XCTAssertEqual(try FileTree.digest(fixture, workspace: alias), try FileTree.digest(fixture, workspace: Paths.physicalURL(directory)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["source"])
    }
}
