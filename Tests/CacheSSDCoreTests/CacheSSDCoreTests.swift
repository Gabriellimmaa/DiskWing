import XCTest
import Foundation
import Darwin
@testable import CacheSSDCore

final class CacheSSDCoreTests: XCTestCase {
    var base: URL!
    override func setUpWithError() throws {
        let testRoot = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        base = testRoot.appendingPathComponent("CacheSSD-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        base = Paths.physicalURL(base)
    }
    override func tearDownWithError() throws { if let base { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.appendingPathComponent("denied").path); try? FileManager.default.removeItem(at: base) } }
    func file(_ name: String, bytes: Int = 4096) throws -> URL {
        let url = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }
    func testScannerDoesNotFollowExternalLinks() throws {
        let root = base.appendingPathComponent("root")
        _ = try file("root/small", bytes: 9)
        let outside = try file("outside/large", bytes: 10000)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("external"), withDestinationURL: outside.deletingLastPathComponent())
        let report = try DiskScanner().scan(root)
        XCTAssertEqual(report.root.logicalBytes, 9)
        XCTAssertEqual(report.root.fileCount, 1)
        XCTAssertTrue(report.root.children.first { $0.name == "external" }!.isSymbolicLink)
    }
    func testHardLinksDoNotDoubleCountAllocatedBlocks() throws {
        let first = try file("root/first", bytes: 8192)
        let second = first.deletingLastPathComponent().appendingPathComponent("second")
        try FileManager.default.linkItem(at: first, to: second)
        var metadata = stat(); XCTAssertEqual(lstat(first.path, &metadata), 0)
        let report = try DiskScanner().scan(first.deletingLastPathComponent())
        XCTAssertEqual(report.root.logicalBytes, 16384)
        XCTAssertEqual(report.root.allocatedBytes, Int64(metadata.st_blocks) * 512)
    }
    func testEntryLimitMarksReportPartial() throws {
        for i in 0..<15 { _ = try file("root/file\(i)", bytes: 3) }
        let report = try DiskScanner(maxEntries: 5).scan(base.appendingPathComponent("root"))
        XCTAssertTrue(report.reachedLimit)
        XCTAssertTrue(report.isPartial)
        XCTAssertLessThanOrEqual(report.examinedEntries, 5)
    }
    func testTruncatedDisplayRetainsCompleteTotalsAndExplainsOmissions() throws {
        for i in 0..<20 { _ = try file("root/file\(i)", bytes: 10) }
        let report = try DiskScanner(childrenPerFolder: 3).scan(base.appendingPathComponent("root"))
        XCTAssertEqual(report.root.logicalBytes, 200)
        XCTAssertEqual(report.root.children.count, 3)
        XCTAssertNotNil(report.root.issue)
        XCTAssertFalse(report.isPartial)
    }
    func testUnreadableDirectoryIsNotReportedAsEmptySuccess() throws {
        let denied = base.appendingPathComponent("denied")
        _ = try file("denied/data")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path) }
        let report = try DiskScanner().scan(base)
        XCTAssertTrue(report.isPartial)
        XCTAssertTrue(report.unreadablePaths.contains(denied.path))
        XCTAssertThrowsError(try FileTree.manifest(base))
    }
    func testPersonalActionsProtectBrowserAndAppData() throws {
        let home = base.appendingPathComponent("home")
        XCTAssertNotNil(PersonalActionPolicy.reasonPreventing(home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/History"), home: home))
        XCTAssertNotNil(PersonalActionPolicy.reasonPreventing(home.appendingPathComponent("Pictures/Photos.photoslibrary/database"), home: home))
        XCTAssertNotNil(PersonalActionPolicy.reasonPreventing(home.appendingPathComponent("Documents/project/node_modules/package"), home: home))
        XCTAssertNotNil(PersonalActionPolicy.reasonPreventing(home.appendingPathComponent("Downloads"), home: home))
        XCTAssertNil(PersonalActionPolicy.reasonPreventing(home.appendingPathComponent("Downloads/archive.zip"), home: home))
    }
    func testManifestRejectsExternalSymlinks() throws {
        let outside = try file("outside")
        let root = base.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertThrowsError(try FileTree.manifest(root))
    }
    func testCopyVerifiesEveryFileAndPreservesRelativeLinks() throws {
        let source = base.appendingPathComponent("source")
        _ = try file("source/nested/data", bytes: 19000)
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "nested/data")
        let target = base.appendingPathComponent("target")
        let manifest = try FileTree.manifest(source)
        try FileTree.copy(source, to: target)
        XCTAssertEqual(manifest, try FileTree.manifest(target))
        XCTAssertThrowsError(try FileTree.copy(source, to: target))
    }
    func testCancelledCopyKeepsSource() throws {
        let source = try file("source/data").deletingLastPathComponent()
        let token = CancellationFlag(); token.cancel()
        XCTAssertThrowsError(try FileTree.copy(source, to: base.appendingPathComponent("target"), cancellation: token))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("data").path))
    }
    func fixture(_ id: String) throws -> (home: URL, volume: VolumeInfo, store: Store, tool: CacheDescriptor) {
        let home = base.appendingPathComponent("home"), volumeRoot = base.appendingPathComponent("SSD")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: volumeRoot, withIntermediateDirectories: true)
        let tool = CacheCatalog.find(id, home: home)!
        try FileManager.default.createDirectory(at: tool.source, withIntermediateDirectories: true)
        try Data("package data".utf8).write(to: tool.source.appendingPathComponent("artifact"))
        let store = Store(base: base.appendingPathComponent("support"))
        let volume = VolumeInfo(uuid: "TEST-UUID", name: "Fixture SSD", path: volumeRoot.path, totalBytes: 100_000_000_000, freeBytes: 90_000_000_000, isInternal: false, isWritable: true)
        var settings = AppSettings(); settings.selectedVolumeUUID = volume.uuid; try store.save(settings)
        return (home, volume, store, tool)
    }
    func testVerifiedMigrationReleasesOnlySelectedCache() throws {
        let f = try fixture("npm")
        let executable = f.home.appendingPathComponent(".npm/_npx/tool/bin.js")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("essential running tool".utf8).write(to: executable)
        let original = try FileTree.manifest(f.tool.source)
        let engine = MigrationEngine(store: f.store, home: f.home, volumeProvider: { _ in f.volume }, verifyNative: false)
        _ = try engine.migrate(toolID: "npm", removeLocal: true)
        XCTAssertEqual(FileTree.measure(f.tool.source).logical, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: executable.path))
        let location = f.store.settings().locations["npm"]!
        let destination = URL(fileURLWithPath: f.volume.path).appendingPathComponent(location.relativePath).appendingPathComponent("_cacache")
        XCTAssertEqual(original, try FileTree.manifest(destination))
    }
    func testDisconnectDuringMigrationPreservesSource() throws {
        let f = try fixture("bun")
        var calls = 0
        let engine = MigrationEngine(store: f.store, home: f.home, volumeProvider: { _ in calls += 1; return calls == 1 ? f.volume : nil }, verifyNative: false)
        XCTAssertThrowsError(try engine.migrate(toolID: "bun", removeLocal: true))
        XCTAssertEqual(try String(contentsOf: f.tool.source.appendingPathComponent("artifact")), "package data")
        XCTAssertNil(f.store.settings().locations["bun"])
    }
    func testFullVolumeIsRejectedWithoutChangingSource() throws {
        let f = try fixture("bun")
        let full = VolumeInfo(uuid: f.volume.uuid, name: f.volume.name, path: f.volume.path, totalBytes: 100, freeBytes: 1, isInternal: false, isWritable: true)
        let engine = MigrationEngine(store: f.store, home: f.home, volumeProvider: { _ in full }, verifyNative: false)
        XCTAssertThrowsError(try engine.migrate(toolID: "bun", removeLocal: true))
        XCTAssertGreaterThan(FileTree.measure(f.tool.source).logical, 0)
    }
    func testForeignVolumeUUIDIsRejected() throws {
        let f = try fixture("bun")
        let wrong = VolumeInfo(uuid: "WRONG", name: f.volume.name, path: f.volume.path, totalBytes: f.volume.totalBytes, freeBytes: f.volume.freeBytes, isInternal: false, isWritable: true)
        let engine = MigrationEngine(store: f.store, home: f.home, volumeProvider: { _ in wrong }, verifyNative: false)
        XCTAssertThrowsError(try engine.migrate(toolID: "bun", removeLocal: true))
    }
    func testRouterFallsBackWhenSSDIsAbsentOrRegistryEscapesRoot() throws {
        let f = try fixture("bun")
        var settings = f.store.settings()
        settings.locations["bun"] = CacheLocation(toolID: "bun", volumeUUID: f.volume.uuid, relativePath: "../../escape", migratedAt: Date(), logicalBytes: 1)
        XCTAssertTrue(CacheRouter.decisions(settings: settings, volumes: [f.volume]).allSatisfy { $0.mode == "local" })
        XCTAssertTrue(CacheRouter.decisions(settings: settings, volumes: []).allSatisfy { $0.path == nil })
    }
    func testRouterUsesCurrentMountPathAndRespectsLocalMode() throws {
        let f = try fixture("bun")
        let data = URL(fileURLWithPath: f.volume.path).appendingPathComponent("MacCaches/data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        var settings = f.store.settings()
        settings.locations["bun"] = CacheLocation(toolID: "bun", volumeUUID: f.volume.uuid, relativePath: "MacCaches/data", migratedAt: Date(), logicalBytes: 1)
        XCTAssertEqual(CacheRouter.decisions(settings: settings, volumes: [f.volume]).first { $0.toolID == "bun" }?.path, data.path)
        settings.useExternal = false
        XCTAssertNil(CacheRouter.decisions(settings: settings, volumes: [f.volume]).first { $0.toolID == "bun" }?.path)
    }
    func testIntegrationIsIdempotentAndPreservesExistingConfiguration() throws {
        let home = base.appendingPathComponent("home"), store = Store(base: base.appendingPathComponent("support"))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let rc = home.appendingPathComponent(".zshrc")
        let original = "export KEEP_ME=yes\nexport TMPDIR=/Volumes/PortableSSD/tmp\n"
        try original.write(to: rc, atomically: true, encoding: .utf8)
        try ShellIntegration.install(helper: URL(fileURLWithPath: "/usr/bin/true"), store: store, home: home)
        try ShellIntegration.install(helper: URL(fileURLWithPath: "/usr/bin/true"), store: store, home: home)
        let installed = try String(contentsOf: rc)
        XCTAssertEqual(installed.components(separatedBy: "# >>> CacheSSD managed integration >>>").count, 2)
        XCTAssertTrue(installed.contains("export KEEP_ME=yes"))
        XCTAssertFalse(installed.contains("export TMPDIR=/Volumes/PortableSSD/tmp"))
        XCTAssertEqual(try String(contentsOf: store.base.appendingPathComponent("zshrc-before-cachessd.txt")), original)
        let syntax = try CommandRunner.run(URL(fileURLWithPath: "/bin/zsh"), ["-n", store.base.appendingPathComponent("integration.zsh").path])
        XCTAssertEqual(syntax.status, 0, syntax.output)
        try (installed + "\nexport ADDED_LATER=kept\n").write(to: rc, atomically: true, encoding: .utf8)
        try ShellIntegration.uninstall(store: store, home: home)
        let removed = try String(contentsOf: rc)
        XCTAssertTrue(removed.contains("ADDED_LATER=kept"))
        XCTAssertFalse(removed.contains("# >>> CacheSSD managed integration >>>"))
    }
    func testCommandTimeoutAndOutputTruncationAreExplicit() throws {
        XCTAssertThrowsError(try CommandRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["3"], timeout: 0.1))
        let output = try CommandRunner.run(URL(fileURLWithPath: "/usr/bin/printf"), ["abcdefghijk"], maxOutputBytes: 4)
        XCTAssertTrue(output.truncated)
        XCTAssertEqual(output.output, "abcd")
    }
    func testShellRoutingReturnsToLocalAndPreservesExplicitOverrides() throws {
        let home = base.appendingPathComponent("home"), store = Store(base: base.appendingPathComponent("support"))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let marker = try file("mounted", bytes: 1)
        let helper = base.appendingPathComponent("fake-helper")
        let body = "#!/bin/sh\nif [ -f '\(marker.path)' ]; then printf 'BUN_INSTALL_CACHE_DIR\\t/Volumes/Fixture/cache\\n'; fi\n"
        try body.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        try ShellIntegration.install(helper: helper, store: store, home: home)
        let integration = store.base.appendingPathComponent("integration.zsh")
        let commands = "source '\(integration.path)'; print -r -- ${BUN_INSTALL_CACHE_DIR:-LOCAL}; source '\(integration.path)'; /bin/rm '\(marker.path)'; _cachessd_route; print -r -- ${BUN_INSTALL_CACHE_DIR:-LOCAL}"
        var env = ProcessInfo.processInfo.environment; env.removeValue(forKey: "BUN_INSTALL_CACHE_DIR")
        let result = try CommandRunner.run(URL(fileURLWithPath: "/bin/zsh"), ["-c", commands], environment: env)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "/Volumes/Fixture/cache\nLOCAL")
        try Data([1]).write(to: marker)
        env["BUN_INSTALL_CACHE_DIR"] = "/custom/cache"
        let custom = try CommandRunner.run(URL(fileURLWithPath: "/bin/zsh"), ["-c", "source '\(integration.path)'; print -r -- $BUN_INSTALL_CACHE_DIR"], environment: env)
        XCTAssertEqual(custom.output.trimmingCharacters(in: .whitespacesAndNewlines), "/custom/cache")
        env.removeValue(forKey: "BUN_INSTALL_CACHE_DIR")
        let live = try CommandRunner.run(URL(fileURLWithPath: "/bin/zsh"), ["-c", "source '\(integration.path)'; export BUN_INSTALL_CACHE_DIR=/live/custom; _cachessd_route; print -r -- $BUN_INSTALL_CACHE_DIR; unset BUN_INSTALL_CACHE_DIR; _cachessd_route; print -r -- $BUN_INSTALL_CACHE_DIR"], environment: env)
        XCTAssertEqual(live.output.trimmingCharacters(in: .whitespacesAndNewlines), "/live/custom\n/Volumes/Fixture/cache")
    }
    func testUnreadableSettingsArePreservedAndRoutingFailsClosed() throws {
        let store = Store(base: base.appendingPathComponent("support"))
        try store.save(AppSettings())
        let bad = Data("{broken JSON".utf8)
        let location = store.base.appendingPathComponent("settings.json")
        try bad.write(to: location)
        XCTAssertTrue(CacheRouter.environment(settings: store.settings()).isEmpty)
        XCTAssertThrowsError(try store.save(AppSettings()))
        XCTAssertEqual(try Data(contentsOf: location), bad)
    }
    func testBusyOpenFilePreventsMigration() throws {
        let f = try fixture("bun")
        let handle = try FileHandle(forReadingFrom: f.tool.source.appendingPathComponent("artifact"))
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/bin/sleep"); child.arguments = ["10"]; child.standardInput = handle
        try child.run()
        defer { child.terminate(); child.waitUntilExit(); try? handle.close() }
        let busy = try BusyInspector.inspect(paths: [f.tool.source])
        XCTAssertTrue(busy.contains { $0.pid == Int(child.processIdentifier) })
        let engine = MigrationEngine(store: f.store, home: f.home, volumeProvider: { _ in f.volume }, verifyNative: false)
        XCTAssertThrowsError(try engine.migrate(toolID: "bun", removeLocal: true))
        XCTAssertGreaterThan(FileTree.measure(f.tool.source).logical, 0)
    }
    func testGradleLockFilesAreNotCopied() throws {
        let root = base.appendingPathComponent("gradle")
        _ = try file("gradle/modules-2/artifact")
        _ = try file("gradle/modules-2.lock")
        _ = try file("gradle/modules-2/gc.properties")
        let target = base.appendingPathComponent("copy")
        try FileTree.copy(root, to: target, tool: "gradle")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("modules-2.lock").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("modules-2/gc.properties").path))
        XCTAssertEqual(try FileTree.manifest(root, tool: "gradle"), try FileTree.manifest(target, tool: "gradle"))
    }
    func testNativeToolValidationUsesOnlyIsolatedCaches() throws {
        guard ProcessInfo.processInfo.environment["DISKWING_RUN_NATIVE_TESTS"] == "1" else { throw XCTSkip("Set DISKWING_RUN_NATIVE_TESTS=1 to run installed-tool checks") }
        let commands = [("npm","npm"),("bun","bun"),("cocoapods","pod"),("pip","python3"),("uv","uv"),("homebrew","brew")]
        for (id,command) in commands {
            guard ToolLocator.locate(command) != nil else { XCTFail("Native check requested but \(command) was not found"); continue }
            let f = try fixture(id)
            let engine = MigrationEngine(store: f.store, home: f.home, volumeProvider: { _ in f.volume }, verifyNative: true)
            _ = try engine.migrate(toolID: id, removeLocal: false)
            XCTAssertNotNil(f.store.settings().locations[id], "Native validation: \(id)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.tool.source.appendingPathComponent("artifact").path))
        }
    }
    func testProjectCacheSettingsHavePriorityOverAutomaticRouting() throws {
        let home = base.appendingPathComponent("home"), project = home.appendingPathComponent("project/nested")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "cache=/custom/npm-cache\n".write(to: project.deletingLastPathComponent().appendingPathComponent(".npmrc"), atomically: true, encoding: .utf8)
        try "[install.cache]\ndir = '/custom/bun-cache'\n".write(to: project.deletingLastPathComponent().appendingPathComponent("bunfig.toml"), atomically: true, encoding: .utf8)
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "npm", directory: project, home: home))
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "bun", directory: project, home: home))
        try "[tool.other]\ncache-dir = '/unrelated'\n".write(to: project.appendingPathComponent("pyproject.toml"), atomically: true, encoding: .utf8)
        XCTAssertFalse(CacheRouter.hasCustomPreference(toolID: "uv", directory: project, home: home))
        try "[tool.uv]\ncache-dir = '/custom/uv-cache'\n".write(to: project.appendingPathComponent("pyproject.toml"), atomically: true, encoding: .utf8)
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "uv", directory: project, home: home))
    }
    func testNativeGradleValidationPreservesLocalDistributions() throws {
        guard ProcessInfo.processInfo.environment["DISKWING_RUN_NATIVE_TESTS"] == "1" else { throw XCTSkip("Set DISKWING_RUN_NATIVE_TESTS=1 to run installed-tool checks") }
        let localWrapper = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gradle/wrapper")
        guard FileManager.default.fileExists(atPath: localWrapper.path) else { throw XCTSkip("No local Gradle distribution available") }
        let f = try fixture("gradle")
        let localLink = f.home.appendingPathComponent(".gradle/wrapper")
        try FileManager.default.createSymbolicLink(at: localLink, withDestinationURL: localWrapper)
        let engine = MigrationEngine(store: f.store, home: f.home, volumeProvider: { _ in f.volume }, verifyNative: true)
        _ = try engine.migrate(toolID: "gradle", removeLocal: false)
        let location = f.store.settings().locations["gradle"]!
        let externalHome = URL(fileURLWithPath: f.volume.path).appendingPathComponent(location.relativePath)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: externalHome.appendingPathComponent("wrapper").path), localLink.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.tool.source.appendingPathComponent("artifact").path))
    }
    func testBunAndUvOriginalCachesRemainAvailableToExistingEnvironments() throws {
        for id in ["bun", "uv"] {
            let f = try fixture(id)
            let engine = MigrationEngine(store: f.store, home: f.home, volumeProvider: { _ in f.volume }, verifyNative: false)
            _ = try engine.migrate(toolID: id, removeLocal: true)
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.tool.source.appendingPathComponent("artifact").path))
            XCTAssertNotNil(f.store.settings().locations[id])
        }
    }
    func testShellIntegrationPreservesDotfileLinksAndPermissions() throws {
        let home = base.appendingPathComponent("home"), store = Store(base: base.appendingPathComponent("support"))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let original = try file("dotfiles/zshrc", bytes: 10), rc = home.appendingPathComponent(".zshrc")
        try FileManager.default.createSymbolicLink(at: rc, withDestinationURL: original)
        XCTAssertThrowsError(try ShellIntegration.install(helper: URL(fileURLWithPath: "/usr/bin/true"), store: store, home: home))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: rc.path), original.path)
        try FileManager.default.removeItem(at: rc)
        try "export ORIGINAL=yes\n".write(to: rc, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rc.path)
        try ShellIntegration.install(helper: URL(fileURLWithPath: "/usr/bin/true"), store: store, home: home)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: rc.path)[.posixPermissions]) as? NSNumber, NSNumber(value: 0o600))
        try ShellIntegration.uninstall(store: store, home: home)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: rc.path)[.posixPermissions]) as? NSNumber, NSNumber(value: 0o600))
    }
}
