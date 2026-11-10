import XCTest
import Darwin
@testable import CacheSSDCore

/// Explicit opt-in: only blank images created by this fixture are mounted/detached.
final class FilesystemQualificationTests: XCTestCase {
    var root: URL!
    var home: URL!
    var store: Store!
    var image: URL!
    var mount: URL?
    var device: String?
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["DISKWING_RUN_FILESYSTEM_TESTS"] == "1" else { throw XCTSkip("Opt in to disposable filesystem-image qualification") }
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(base).appendingPathComponent("DiskWing-filesystem-\(UUID().uuidString)")
        home = root.appendingPathComponent("home"); image = root.appendingPathComponent("fixture.sparseimage")
        try FileManager.default.createDirectory(at:home.appendingPathComponent("Downloads"),withIntermediateDirectories:true)
        store = Store(base:root.appendingPathComponent("support"))
    }
    override func tearDownWithError() throws {
        if let device {
            let result = try CommandRunner.run(URL(fileURLWithPath:"/usr/bin/hdiutil"),["detach",device],timeout:30)
            guard result.status == 0 else { XCTFail("Disposable image still mounted; fixture retained for recovery"); return }
        }
        if let root { try FileManager.default.removeItem(at:root) }
    }
    func attach(_ filesystem: String, readonly: Bool = false, size: String = "2g") throws -> URL {
        let hdiutil = URL(fileURLWithPath:"/usr/bin/hdiutil")
        if filesystem == "ExFAT" { image = root.appendingPathComponent("fixture.dmg") }
        var createArguments = ["create","-size",size,"-fs",filesystem,"-type",filesystem == "ExFAT" ? "UDIF" : "SPARSE","-volname","DW"+UUID().uuidString.prefix(6)]
        // hdiutil's implicit partition layout can fail when formatting ExFAT.
        if filesystem == "ExFAT" { createArguments += ["-layout","MBRSPUD"] }
        let created = try CommandRunner.run(hdiutil,createArguments+[image.path],timeout:90)
        guard created.status == 0 else { throw CacheSSDError.message("Disposable image creation failed: " + created.output) }
        var arguments = ["attach","-nobrowse","-plist",image.path]
        if readonly { arguments.insert("-readonly",at:1) }
        let result = try CommandRunner.run(hdiutil,arguments,timeout:90)
        guard result.status == 0, let value = try PropertyListSerialization.propertyList(from:Data(result.output.utf8),format:nil) as? [String:Any],
              let entities = value["system-entities"] as? [[String:Any]], let entry = entities.first(where: { $0["mount-point"] != nil }),
              let mounted = entry["mount-point"] as? String, let attached = entry["dev-entry"] as? String, attached.hasPrefix("/dev/disk") else { throw CacheSSDError.message("Disposable image attachment failed: " + result.output) }
        device = attached; mount = URL(fileURLWithPath:mounted)
        return mount!
    }
    func source() throws -> URL {
        let directory = home.appendingPathComponent("Downloads/payload")
        try FileManager.default.createDirectory(at:directory.appendingPathComponent("nested"),withIntermediateDirectories:true)
        let file = directory.appendingPathComponent("nested/é-file.txt")
        try Data("preserved data".utf8).write(to:file)
        try FileManager.default.setAttributes([.posixPermissions:0o640],ofItemAtPath:file.path)
        var times = [timespec(tv_sec:1_500_000_000,tv_nsec:123_456_789),timespec(tv_sec:1_500_000_000,tv_nsec:123_456_789)]
        XCTAssertEqual(utimensat(AT_FDCWD,file.path,&times,0),0)
        for name in ["com.apple.ResourceFork","org.diskwing.fixture"] {
            let bytes = Data("metadata".utf8)
            XCTAssertEqual(bytes.withUnsafeBytes { setxattr(file.path,name,$0.baseAddress,bytes.count,0,0) },0)
        }
        let acl = try CommandRunner.run(URL(fileURLWithPath:"/bin/chmod"),["+a","everyone allow read,readattr,readextattr,readsecurity",file.path])
        guard acl.status == 0 else { throw CacheSSDError.message("Fixture ACL setup failed: " + acl.output) }
        try FileManager.default.linkItem(at:file,to:directory.appendingPathComponent("hard-link"))
        return directory
    }
    func fakeTrash(_ source: URL) throws -> URL? {
        let trash = root.appendingPathComponent("private-trash")
        try FileManager.default.moveItem(at:source,to:trash); return trash
    }
    func record(_ scenario: String, filesystem: String, extra: [String:Any] = [:]) throws {
        guard let directory = ProcessInfo.processInfo.environment["DISKWING_FILESYSTEM_REPORT_DIR"] else { return }
        let folder = URL(fileURLWithPath:directory)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var value: [String:Any] = ["scenario":scenario,"filesystem":filesystem,"result":"passed","date":ISO8601DateFormatter().string(from:Date()),"scope":"Disposable disk image; no physical cable removal"]
        for (key,item) in extra { value[key] = item }
        try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(scenario+".json"))
    }
    func testAPFSCrossVolumeMoveAndVerifiedRecoveryPreserveMetadata() throws {
        let mounted = try attach("APFS"), source = try source(), before = try FileTree.digest(source)
        let destination = mounted.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        var a = stat(), b = stat(); XCTAssertEqual(lstat(source.path,&a),0); XCTAssertEqual(lstat(mounted.path,&b),0)
        XCTAssertNotEqual(a.st_dev,b.st_dev,"This must be a genuine cross-volume copy")
        let actions = PersonalActions(home:home,store:store,trashHandler:fakeTrash,checkpoint:{ if $0.phase == .completed { throw CacheSSDError.message("Injected post-trash interruption") } })
        XCTAssertThrowsError(try actions.move(source,to:destination))
        let journal = try XCTUnwrap(store.operations().first)
        let copied = destination.appendingPathComponent("payload")
        XCTAssertEqual(try FileTree.digest(copied),before)
        XCTAssertFalse(FileManager.default.fileExists(atPath:source.path))
        // Keep the original privately; force recovery from the external verified copy.
        try FileManager.default.moveItem(at:root.appendingPathComponent("private-trash"),to:root.appendingPathComponent("preserved-original"))
        try RecoveryManager(store:store,home:home).restoreSource(id:journal.id)
        XCTAssertEqual(try FileTree.digest(source),before)
        XCTAssertEqual(try FileTree.digest(copied),before)
        try record("apfs-move-recovery",filesystem:"APFS",extra:["bytesACLResourceForkModeNanosecondMtimeVerified":true,"originalPreserved":true,"verifiedCopyPreserved":true])
    }
    func testExFATIsRejectedBeforeSourceReleaseOrCopyPublication() throws {
        let mounted = try attach("ExFAT",size:"128m"), source = try source(), before = try FileTree.digest(source)
        XCTAssertEqual(try mounted.resourceValues(forKeys:[.volumeSupportsExtendedSecurityKey]).volumeSupportsExtendedSecurity,false)
        XCTAssertThrowsError(try FileTree.validateDestination(mounted))
        let destination = mounted.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        XCTAssertThrowsError(try PersonalActions(home:home,store:store,trashHandler:fakeTrash).move(source,to:destination))
        XCTAssertEqual(try FileTree.digest(source),before)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:destination.path).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("private-trash").path))
        XCTAssertTrue(store.operations().isEmpty)
        try record("exfat-safe-refusal",filesystem:"ExFAT",extra:["originalPreserved":true,"destinationUnchanged":true])
    }
    func testReadOnlyAPFSRefusesCopyWithoutChangingOriginal() throws {
        let mounted = try attach("APFS",readonly:true), source = try source(), before = try FileTree.digest(source)
        XCTAssertThrowsError(try FileTree.copy(source,to:mounted.appendingPathComponent("unpublished")))
        XCTAssertEqual(try FileTree.digest(source),before)
        XCTAssertFalse(FileManager.default.fileExists(atPath:mounted.appendingPathComponent("unpublished").path))
        try record("apfs-readonly-refusal",filesystem:"APFS",extra:["originalPreserved":true])
    }
    func testLowSpaceOnDisposableAPFSPreventsCacheMigration() throws {
        let mounted = try attach("APFS",size:"1g"), tool = try XCTUnwrap(CacheCatalog.find("npm",home:home))
        try FileManager.default.createDirectory(at:tool.source,withIntermediateDirectories:true)
        let file = tool.source.appendingPathComponent("artifact")
        FileManager.default.createFile(atPath:file.path,contents:nil)
        let sourceHandle = try FileHandle(forWritingTo:file); try sourceHandle.truncate(atOffset:67_108_864); try sourceHandle.close()
        let filler = mounted.appendingPathComponent("fixture-space-reservation")
        FileManager.default.createFile(atPath:filler.path,contents:nil)
        let handle = try FileHandle(forWritingTo:filler), block = Data(repeating:65,count:1_048_576)
        var written = 0
        while Volumes.free(at:mounted) >= 603_979_776 && written < 896 {
            try handle.write(contentsOf:block); written += 1
            if written % 32 == 0 { try handle.synchronize() }
        }
        try handle.synchronize(); try handle.close()
        let free = Volumes.free(at:mounted)
        XCTAssertLessThan(free,603_979_776)
        let volume = VolumeInfo(uuid:"DISPOSABLE-APFS",name:"Test",path:mounted.path,totalBytes:1_073_741_824,freeBytes:free,isInternal:false,isWritable:true)
        var settings = AppSettings(); settings.selectedVolumeUUID = volume.uuid; try store.save(settings)
        let before = try FileTree.digest(tool.source)
        XCTAssertThrowsError(try MigrationEngine(store:store,home:home,volumeProvider:{ _ in volume },verifyNative:false).migrate(toolID:"npm",removeLocal:true))
        XCTAssertEqual(try FileTree.digest(tool.source),before)
        XCTAssertTrue(store.operations().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:mounted.appendingPathComponent("MacCaches").path))
        try record("apfs-low-space-refusal",filesystem:"APFS",extra:["originalPreserved":true,"diskReservationMiB":written])
    }
}
