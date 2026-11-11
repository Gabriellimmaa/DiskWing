import XCTest
import Foundation
import Darwin
@testable import CacheSSDCore

final class GraphicalProcessFilesTests: XCTestCase {
    private var root: URL!
    private var destination: URL!
    private let selfPID = Int(getpid())
    private let generous = GraphicalProcessFiles.Limits(durationSeconds: 2)
    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-process-files-\(UUID().uuidString)")
        destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func file(_ name: String, parent: URL? = nil) throws -> URL {
        let directory = parent ?? destination!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 42, count: 4096).write(to: url); return url
    }
    private func descriptor(_ file: URL, flags: Int32) throws -> Int32 {
        let descriptor = open(file.path, flags | O_CLOEXEC)
        guard descriptor >= 0 else { throw CacheSSDError.message("Generated process fixture could not open its descriptor") }
        return descriptor
    }
    private func snapshot(managedSource: URL? = nil) throws -> GraphicalProcessFileSnapshot {
        try GraphicalProcessFiles.snapshot(pids: [selfPID], destination: destination, managedSource: managedSource, limits: generous)
    }
    func testRealReadWriteAndReadWriteDescriptorsExposeTheirActualModesAndIdentities() throws {
        let input = try file("read"), output = try file("write"), both = try file("both")
        let readFD = try descriptor(input, flags: O_RDONLY), writeFD = try descriptor(output, flags: O_WRONLY), bothFD = try descriptor(both, flags: O_RDWR)
        defer { close(readFD); close(writeFD); close(bothFD) }
        let evidence = try snapshot()
        let read = try XCTUnwrap(evidence.files.first { $0.descriptor == readFD })
        let write = try XCTUnwrap(evidence.files.first { $0.descriptor == writeFD })
        let mixed = try XCTUnwrap(evidence.files.first { $0.descriptor == bothFD })
        XCTAssertTrue(read.readable); XCTAssertFalse(read.writable)
        XCTAssertFalse(write.readable); XCTAssertTrue(write.writable)
        XCTAssertTrue(mixed.readable); XCTAssertTrue(mixed.writable)
        XCTAssertEqual(read.fileIdentity.device, try FileIdentity(input).device)
        XCTAssertEqual(read.fileIdentity.inode, try FileIdentity(input).inode)
        XCTAssertEqual(read.relativePath, "read")
        XCTAssertEqual(evidence.readers, [selfPID]); XCTAssertEqual(evidence.writers, [selfPID])
        XCTAssertTrue(GraphicalProcessFiles.isCurrent(read.process))
    }
    func testTouchedClosedFilesAndDirectoriesDoNotBecomeReadOrWriteEvidence() throws {
        _ = try file("touched-marker")
        let directoryFD = try descriptor(destination, flags: O_RDONLY | O_DIRECTORY)
        defer { close(directoryFD) }
        let evidence = try snapshot()
        XCTAssertTrue(evidence.files.isEmpty); XCTAssertTrue(evidence.readers.isEmpty); XCTAssertTrue(evidence.writers.isEmpty)
    }
    func testSiblingPrefixAndSymlinkEscapeCannotBeAttributedToTheDestination() throws {
        let sibling = root.appendingPathComponent("destination-other")
        let outside = try file("outside", parent: sibling)
        let outsideFD = try descriptor(outside, flags: O_RDWR)
        defer { close(outsideFD) }
        try FileManager.default.createSymbolicLink(at: destination.appendingPathComponent("escape"), withDestinationURL: sibling)
        let escapedFD = try descriptor(destination.appendingPathComponent("escape/outside"), flags: O_RDONLY)
        defer { close(escapedFD) }
        let evidence = try snapshot()
        XCTAssertTrue(evidence.files.isEmpty)
    }
    func testManagedRootAliasWorksOnlyWhenItResolvesToTheExactDestination() throws {
        let input = try file("entry"), alias = root.appendingPathComponent("managed-source")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: destination)
        let fd = try descriptor(alias.appendingPathComponent("entry"), flags: O_RDONLY)
        defer { close(fd) }
        let evidence = try snapshot(managedSource: alias)
        XCTAssertEqual(evidence.files.first(where: { $0.descriptor == fd })?.fileIdentity.inode, try FileIdentity(input).inode)
        let compatibility = GraphicalCacheProcessProbe.accesses(pids: [selfPID], destination: destination, source: alias)
        XCTAssertTrue(compatibility.read.contains(selfPID)); XCTAssertFalse(compatibility.write.contains(selfPID))
    }
    func testADeletedDescriptorCannotAuthenticateAReplacementPath() throws {
        let original = try file("entry"), fd = try descriptor(original, flags: O_RDONLY)
        defer { close(fd) }
        try FileManager.default.removeItem(at: original)
        _ = try file("entry")
        XCTAssertFalse(try snapshot().files.contains { $0.descriptor == fd })
    }
    func testMemoryMappingWithoutAnOpenDescriptorIsNotInferredAsARead() throws {
        let input = try file("mapped"), fd = try descriptor(input, flags: O_RDONLY)
        let mapping = mmap(nil, 4096, PROT_READ, MAP_PRIVATE, fd, 0)
        guard mapping != MAP_FAILED else { close(fd); throw CacheSSDError.message("Generated mapping fixture failed") }
        close(fd); defer { munmap(mapping, 4096) }
        XCTAssertTrue(try snapshot().files.isEmpty)
    }
    func testCancellationAndZeroBudgetsAreExplicitAndInvalidPIDsCannotOverflow() throws {
        let flag = CancellationFlag(); flag.cancel()
        XCTAssertThrowsError(try GraphicalProcessFiles.snapshot(pids: [selfPID], destination: destination, cancellation: flag))
        let budget = try GraphicalProcessFiles.snapshot(pids: [selfPID], destination: destination, limits: .init(maximumTotalDescriptors: 0))
        XCTAssertTrue(budget.limitReached); XCTAssertTrue(budget.files.isEmpty)
        let deadline = try GraphicalProcessFiles.snapshot(pids: [selfPID], destination: destination, limits: .init(durationSeconds: 0))
        XCTAssertTrue(deadline.limitReached); XCTAssertTrue(deadline.files.isEmpty)
        XCTAssertNil(GraphicalProcessFiles.processIdentity(pid: Int.max))
        XCTAssertNil(GraphicalProcessFiles.processIdentity(pid: -1))
        let invalid = try GraphicalProcessFiles.snapshot(pids: [0, -1, Int.max], destination: destination, limits: generous)
        XCTAssertTrue(invalid.files.isEmpty); XCTAssertEqual(invalid.queriedDescriptors, 0)
    }
    func testRootSymlinksRemainForbidden() throws {
        let alias = root.appendingPathComponent("unknown-root")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: destination)
        XCTAssertThrowsError(try GraphicalProcessFiles.snapshot(pids: [selfPID], destination: alias))
    }
}
