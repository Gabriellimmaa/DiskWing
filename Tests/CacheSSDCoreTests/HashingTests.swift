import XCTest
import CryptoKit
@testable import CacheSSDCore

final class HashingTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(base).appendingPathComponent("DiskWing-hashing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func hex(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    func testChunkedHashAndPersistedFileDigestMatchHistoricalBytes() throws {
        let file = root.appendingPathComponent("generated.bin")
        var data = Data(repeating: 21, count: 3 * 1_048_576 + 37)
        for offset in stride(from: 0, to: data.count, by: 4093) { data[offset] = UInt8(truncatingIfNeeded: offset) }
        try data.write(to: file)
        let expectedHash = hex(data)
        XCTAssertEqual(try FileTree.hash(file), expectedHash)
        var historicalInput = Data(try FileTree.metadataDigest(file).utf8)
        historicalInput.append(Data(expectedHash.utf8))
        XCTAssertEqual(try FileTree.digest(file, workspace: root), hex(historicalInput))
        XCTAssertEqual(try Data(contentsOf: file), data)
    }
    func testEmptyAndCancelledHashesKeepExistingSemanticsAndPreserveFiles() throws {
        let empty = root.appendingPathComponent("empty"), populated = root.appendingPathComponent("populated")
        try Data().write(to: empty); try Data("preserved bytes".utf8).write(to: populated)
        XCTAssertEqual(try FileTree.hash(empty), hex(Data()))
        let token = CancellationFlag(); token.cancel()
        XCTAssertThrowsError(try FileTree.hash(populated, cancellation: token))
        XCTAssertEqual(try Data(contentsOf: populated), Data("preserved bytes".utf8))
        XCTAssertEqual(try FileTree.hash(populated), hex(Data("preserved bytes".utf8)))
    }
}
