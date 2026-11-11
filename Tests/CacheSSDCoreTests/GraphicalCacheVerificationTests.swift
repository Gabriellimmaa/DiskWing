import XCTest
import Foundation
import Darwin
@testable import CacheSSDCore

final class GraphicalCacheVerificationTests: XCTestCase {
    var root: URL!
    var source: URL!
    var target: URL!
    var reference: URL!
    override func setUpWithError() throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(base).appendingPathComponent("DiskWing-opaque-copy-\(UUID().uuidString)")
        source = root.appendingPathComponent("source"); target = root.appendingPathComponent("target"); reference = root.appendingPathComponent("reference")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reference, withIntermediateDirectories: false)
        try Data("generated cache bytes".utf8).write(to: source.appendingPathComponent("entry"))
        try attribute(source, Data("0081;00000000;GeneratedFixture;".utf8))
        try attribute(source.appendingPathComponent("entry"), Data("0081;00000000;GeneratedFixture;".utf8))
        try FileTree.copy(source, to: target)
    }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at: root) } }
    func attribute(_ path: URL, _ bytes: Data) throws {
        let result = bytes.withUnsafeBytes { setxattr(path.path, "com.apple.quarantine", $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }
        guard result == 0 else { throw CacheSSDError.message("Generated quarantine attribute setup failed") }
    }
    func raw(_ path: URL) throws -> Data {
        let size = getxattr(path.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW)
        guard size >= 0 else { throw CacheSSDError.message("Generated quarantine attribute unavailable") }
        var bytes = [UInt8](repeating: 0, count: max(1, size))
        guard getxattr(path.path, "com.apple.quarantine", &bytes, size, 0, XATTR_NOFOLLOW) == size else { throw CacheSSDError.message("Generated quarantine attribute changed") }
        return Data(bytes.prefix(size))
    }
    func verify() throws -> GraphicalCacheVerificationProof {
        try GraphicalCacheVerification.verify(source: source, target: target, sourceAnchor: root, targetAnchor: root,
            expectedSource: GraphicalCacheDirectoryIdentity(source), expectedTarget: GraphicalCacheDirectoryIdentity(target),
            referenceRoot: reference, referenceAnchor: root, cancellation: CancellationFlag())
    }
    func testOpaqueStandardCopyResultIsKeptUnmodifiedAndProven() throws {
        let sourceBefore = try raw(source), targetBefore = try raw(target)
        let proof = try verify()
        XCTAssertEqual(proof.policyVersion, 1); XCTAssertEqual(proof.verifiedEntries, 2)
        XCTAssertFalse(proof.quarantine.isEmpty)
        XCTAssertEqual(try raw(source), sourceBefore); XCTAssertEqual(try raw(target), targetBefore)
        XCTAssertTrue(proof.quarantine.allSatisfy { $0.resultSHA256 == $0.referenceSHA256 && $0.sourceSHA256 != nil })
    }
    func testMissingQuarantineIsRefusedEvenIfOtherMetadataAndBytesMatch() throws {
        XCTAssertEqual(removexattr(target.appendingPathComponent("entry").path, "com.apple.quarantine", XATTR_NOFOLLOW), 0)
        XCTAssertThrowsError(try verify())
        XCTAssertFalse(try raw(source.appendingPathComponent("entry")).isEmpty)
    }
    func testStagingMetadataIsReappliedOnlyByStandardCopyAndSourceIsUnchanged() throws {
        let original = try raw(source)
        let changed = Data("0081;00000000;DifferentFixture;".utf8)
        try attribute(target, changed)
        let proof = try verify()
        XCTAssertEqual(try raw(source), original)
        XCTAssertNotEqual(try raw(target), changed)
        XCTAssertTrue(proof.quarantine.allSatisfy { $0.resultSHA256 == $0.referenceSHA256 })
    }
    func testCopyTimeOpaqueValuesConvergeByStandardMetadataCopyWithoutChangingSource() throws {
        let entry = source.appendingPathComponent("entry")
        let value = Data("0081;\(String(Int(Date().timeIntervalSince1970) - 5, radix: 16));GeneratedFixture;".utf8)
        try attribute(entry, value)
        Thread.sleep(forTimeInterval: 1.05)
        let proof = try verify()
        XCTAssertEqual(try raw(entry), value)
        let item = try XCTUnwrap(proof.quarantine.first { $0.sourceValueBase64 == value.base64EncodedString() })
        XCTAssertEqual(item.resultValueBase64, item.referenceValueBase64)
        XCTAssertEqual(item.resultValueBase64, try raw(target.appendingPathComponent("entry")).base64EncodedString())
        XCTAssertEqual(try String(contentsOf: entry), "generated cache bytes")
    }
    func testOtherMetadataAndPayloadRemainStrict() throws {
        try Data("changed bytes".utf8).write(to: target.appendingPathComponent("entry"))
        XCTAssertThrowsError(try verify())
        XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("entry")), "generated cache bytes")
    }
    func testReferenceCannotFollowReplacedRoot() throws {
        let expected = try GraphicalCacheDirectoryIdentity(target), held = root.appendingPathComponent("held")
        try FileManager.default.moveItem(at: target, to: held)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: held)
        XCTAssertThrowsError(try GraphicalCacheVerification.verify(source: source, target: target, sourceAnchor: root, targetAnchor: root,
            expectedSource: GraphicalCacheDirectoryIdentity(source), expectedTarget: expected, referenceRoot: reference, referenceAnchor: root, cancellation: CancellationFlag()))
    }
}
