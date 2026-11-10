import XCTest
import Foundation
@testable import CacheSSDCore

/// Separate opt-in; all homes, projects, caches and records are generated.
final class ExpandedNativeWorkflowTests: XCTestCase {
    var root: URL!
    var home: URL!
    var project: URL!
    var disk: URL!
    var store: Store!
    var volume: VolumeInfo!
    var environment: [String: String]!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["DISKWING_RUN_EXPANDED_NATIVE_TESTS"] == "1" else { throw XCTSkip("Set DISKWING_RUN_EXPANDED_NATIVE_TESTS=1 for generated expanded native workflows") }
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-expanded-native-\(UUID().uuidString)")
        home = root.appendingPathComponent("home"); project = root.appendingPathComponent("project"); disk = root.appendingPathComponent("SSD")
        for directory in [home!, project!, disk!, root.appendingPathComponent("tmp")] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        store = Store(base: root.appendingPathComponent("support"))
        volume = VolumeInfo(uuid: "GENERATED-NATIVE-SSD", name: "Generated SSD", path: disk.path, totalBytes: 1_000_000_000_000, freeBytes: Volumes.free(at: disk), isInternal: false, isWritable: true)
        var settings = AppSettings(); settings.selectedVolumeUUID = volume.uuid; try store.save(settings)
        var bins = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        for name in ["node", "yarn", "go", "ccache", "clang"] { if let executable = ToolLocator.locate(name) { bins.insert(executable.deletingLastPathComponent().path, at: 0) } }
        environment = ["HOME": home.path, "PATH": bins.joined(separator: ":"), "TMPDIR": root.appendingPathComponent("tmp").path,
                       "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8", "CI": "1", "YARN_IGNORE_PATH": "1",
                       "NPM_CONFIG_USERCONFIG": "/dev/null", "npm_config_registry": "https://registry.npmjs.org",
                       "GOTOOLCHAIN": "local", "GOENV": "off", "GOPROXY": "off", "GOSUMDB": "off", "GOPATH": root.appendingPathComponent("gopath").path]
    }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at: root) } }
    func executable(_ name: String) throws -> URL {
        guard let executable = ToolLocator.locate(name) else { throw XCTSkip("Native tool unavailable: \(name); no qualification established") }
        return executable
    }
    func engine() -> MigrationEngine {
        MigrationEngine(store: store, home: home, volumeProvider: { _ in self.volume }, verifyNative: true, busyCheck: { _, _ in [] }, adapterInspector: { descriptor in
            AdapterStatus(toolID: descriptor.id, adapterVersion: CacheAdapters.version, version: nil, effectiveCachePath: nil, state: "native-available", explanation: "Generated native fixture", canReleaseSource: false)
        })
    }
    @discardableResult func run(_ executable: URL, _ arguments: [String], env: [String:String]? = nil) throws -> CommandResult {
        var values = env ?? environment!; values["PATH"] = executable.deletingLastPathComponent().path + ":" + (values["PATH"] ?? "")
        let result = try CommandRunner.run(executable, arguments, environment: values, timeout: 240, directory: project, maxOutputBytes: 524_288)
        guard result.status == 0, !result.truncated else { throw CacheSSDError.message("Generated expanded native workflow failed (\(executable.lastPathComponent), \(result.status)): " + result.output.suffix(2000)) }
        return result
    }
    func record(_ id: String, executable: URL, workflow: String, sourceRetained: Bool, versionArguments: [String] = ["--version"]) throws {
        guard let reportDirectory = ProcessInfo.processInfo.environment["DISKWING_EXPANDED_NATIVE_REPORT_DIR"] else { return }
        let result = try run(executable, versionArguments)
        let output = URL(fileURLWithPath: reportDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let report: [String: Any] = ["toolID": id, "versionOutput": result.output.trimmingCharacters(in: .whitespacesAndNewlines), "adapterVersion": CacheAdapters.version,
                                   "workflow": workflow, "sourceRetained": sourceRetained, "localFallback": true, "newWritesOnSSD": true,
                                   "scope": "generated fixtures only; no physical disconnect or human acceptance", "date": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent(id + ".json"), options: .withoutOverwriting)
    }
    func nodeProject(_ package: String = "is-number", version: String = "7.0.0", pnp: Bool = false) throws {
        let object: [String: Any] = ["name": "generated-diskwing-native", "version": "1.0.0", "private": true,
                                  "dependencies": [package: version], "installConfig": ["pnp": pnp]]
        try JSONSerialization.data(withJSONObject: object, options: .sortedKeys).write(to: project.appendingPathComponent("package.json"))
    }
    func yarnArguments(offline: Bool = false, pnp: Bool = false) -> [String] {
        ["install", "--ignore-scripts", "--non-interactive", "--no-progress", "--no-default-rc", "--registry", "https://registry.npmjs.org"] + (offline ? ["--offline"] : []) + (pnp ? ["--enable-pnp"] : [])
    }
    func verifyNode(pnp: Bool = false, package: String = "is-number") throws {
        _ = try run(executable("node"), (pnp ? ["--require", "./.pnp.js"] : []) + ["-e", "if (!require('\(package)')) process.exit(1)"])
    }
    func testYarnClassicMigrationReuseNewWritesFallbackAndPnPRetention() throws {
        let yarn = try executable("yarn")
        guard CacheAdapters.yarnClassicVersion(home: home) != nil else { throw XCTSkip("Only identified Yarn Classic 1.22 installations qualify") }
        let tool = try XCTUnwrap(CacheCatalog.find("yarn", home: home))
        environment[tool.environmentKey] = tool.source.deletingLastPathComponent().path
        try nodeProject(pnp: true)
        _ = try run(yarn, yarnArguments(pnp: true)); try verifyNode(pnp: true)
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "yarn", directory: project, home: home, processEnvironment: [:]))
        let sourceDigest = try FileTree.digest(tool.source)
        _ = try engine().migrate(toolID: tool.id, removeLocal: false)
        XCTAssertEqual(try FileTree.digest(tool.source), sourceDigest)
        try verifyNode(pnp: true)
        let location = try XCTUnwrap(store.settings().locations[tool.id])
        var external = environment!; external[tool.environmentKey] = disk.appendingPathComponent(location.relativePath).path
        try FileManager.default.removeItem(at: project.appendingPathComponent(".pnp.js"))
        try nodeProject()
        _ = try run(yarn, yarnArguments(offline: true), env: external); try verifyNode()
        let externalPayload = tool.payload(at: disk.appendingPathComponent(location.relativePath))
        let beforeWrite = FileTree.measure(externalPayload).logical
        try nodeProject("is-odd", version: "3.0.1")
        _ = try run(yarn, yarnArguments(), env: external); try verifyNode(package: "is-odd")
        XCTAssertGreaterThan(FileTree.measure(externalPayload).logical, beforeWrite)
        XCTAssertEqual(CacheRouter.decisions(settings: store.settings(), volumes: []).first { $0.toolID == tool.id }?.mode, "local")
        try nodeProject()
        try FileManager.default.removeItem(at: project.appendingPathComponent("node_modules"))
        _ = try run(yarn, yarnArguments(offline: true)); try verifyNode()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tool.source.path))
        try record(tool.id, executable: yarn, workflow: "Classic PnP origin retained and executable; migrated cache reused offline; new dependency written on SSD; absent-volume local cache reused", sourceRetained: true)
    }
    func testYarnClassicPreparedEmptyCacheWritesOnSSDWithoutCreatingOrigin() throws {
        let yarn = try executable("yarn")
        guard CacheAdapters.yarnClassicVersion(home: home) != nil else { throw XCTSkip("Only identified Yarn Classic 1.22 installations qualify") }
        let tool = try XCTUnwrap(CacheCatalog.find("yarn", home: home))
        _ = try engine().prepareFutureCache(toolID: tool.id)
        let location = try XCTUnwrap(store.settings().locations[tool.id])
        var external = environment!; external[tool.environmentKey] = disk.appendingPathComponent(location.relativePath).path
        try nodeProject(); _ = try run(yarn, yarnArguments(), env: external); try verifyNode()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tool.source.path))
        XCTAssertGreaterThan(FileTree.measure(tool.payload(at: disk.appendingPathComponent(location.relativePath))).logical, 0)
    }
    func testGoBuildCacheMigrationAndLocalFallback() throws {
        let go = try executable("go"), tool = try XCTUnwrap(CacheCatalog.find("go", home: home))
        environment[tool.environmentKey] = tool.source.path
        try Data("package main\nimport \"fmt\"\nfunc main(){fmt.Print(\"generated\")}\n".utf8).write(to: project.appendingPathComponent("main.go"))
        _ = try run(go, ["build", "-o", "generated", "main.go"])
        let original = try FileTree.digest(tool.source)
        _ = try engine().migrate(toolID: tool.id, removeLocal: false)
        let location = try XCTUnwrap(store.settings().locations[tool.id])
        var external = environment!; external[tool.environmentKey] = disk.appendingPathComponent(location.relativePath).path
        _ = try run(go, ["build", "-o", "generated-external", "main.go"], env: external)
        XCTAssertEqual(try run(project.appendingPathComponent("generated-external"), []).output, "generated")
        try Data("package main\nfunc main(){println(\"new generated cache entry\")}\n".utf8).write(to: project.appendingPathComponent("main.go"))
        let before = try FileTree.digest(disk.appendingPathComponent(location.relativePath))
        _ = try run(go, ["build", "-o", "generated-new", "main.go"], env: external)
        XCTAssertNotEqual(try FileTree.digest(disk.appendingPathComponent(location.relativePath)), before)
        XCTAssertEqual(try FileTree.digest(tool.source), original)
        _ = try run(go, ["build", "-o", "generated-local", "main.go"])
        XCTAssertEqual(CacheRouter.decisions(settings: store.settings(), volumes: []).first { $0.toolID == tool.id }?.mode, "local")
        try record(tool.id, executable: go, workflow: "Generated Go binary compiled and executed through migrated cache; new SSD build entry; local fallback build", sourceRetained: true, versionArguments: ["version"])
    }
    func testGoPreparedEmptyCacheWritesOnSSDWithoutCreatingOrigin() throws {
        let go = try executable("go"), tool = try XCTUnwrap(CacheCatalog.find("go", home: home))
        _ = try engine().prepareFutureCache(toolID: tool.id)
        let location = try XCTUnwrap(store.settings().locations[tool.id])
        var external = environment!; external[tool.environmentKey] = disk.appendingPathComponent(location.relativePath).path
        try Data("package main\nfunc main(){println(\"generated\")}\n".utf8).write(to: project.appendingPathComponent("main.go"))
        _ = try run(go, ["build", "-o", "generated-external", "main.go"], env: external)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tool.source.path))
        XCTAssertGreaterThan(FileTree.measure(disk.appendingPathComponent(location.relativePath)).logical, 0)
    }
    func testCcacheCompilationMigrationAndLocalFallback() throws {
        let ccache = try executable("ccache"), clang = try executable("clang"), tool = try XCTUnwrap(CacheCatalog.find("ccache", home: home))
        environment[tool.environmentKey] = tool.source.path
        try Data("int generated(void){return 42;}\n".utf8).write(to: project.appendingPathComponent("main.c"))
        _ = try run(ccache, [clang.path, "-c", "main.c", "-o", "generated.o"])
        _ = try engine().migrate(toolID: tool.id, removeLocal: false)
        let location = try XCTUnwrap(store.settings().locations[tool.id])
        var external = environment!; external[tool.environmentKey] = disk.appendingPathComponent(location.relativePath).path
        _ = try run(ccache, [clang.path, "-c", "main.c", "-o", "generated-external.o"], env: external)
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("generated.o")), try Data(contentsOf: project.appendingPathComponent("generated-external.o")))
        try Data("int generated(void){return 43;}\n".utf8).write(to: project.appendingPathComponent("main.c"))
        let before = try FileTree.digest(disk.appendingPathComponent(location.relativePath))
        _ = try run(ccache, [clang.path, "-c", "main.c", "-o", "generated-new.o"], env: external)
        XCTAssertNotEqual(try FileTree.digest(disk.appendingPathComponent(location.relativePath)), before)
        _ = try run(ccache, [clang.path, "-c", "main.c", "-o", "generated-local.o"])
        XCTAssertEqual(CacheRouter.decisions(settings: store.settings(), volumes: []).first { $0.toolID == tool.id }?.mode, "local")
        try record(tool.id, executable: ccache, workflow: "Generated C object compiled through migrated cache with equivalent bytes; new SSD cache entry; local fallback compilation", sourceRetained: true)
    }
}
