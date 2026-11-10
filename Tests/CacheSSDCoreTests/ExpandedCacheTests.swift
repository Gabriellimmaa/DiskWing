import XCTest
import Foundation
import Darwin
@testable import CacheSSDCore

final class ExpandedCacheTests: XCTestCase {
    var root: URL!
    var home: URL!
    var disk: URL!
    var store: Store!
    var volume: VolumeInfo!

    override func setUpWithError() throws {
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(parent).appendingPathComponent("DiskWing-expanded-\(UUID().uuidString)")
        home = root.appendingPathComponent("home"); disk = root.appendingPathComponent("SSD")
        for path in [home!, disk!] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
        store = Store(base: root.appendingPathComponent("support"))
        volume = VolumeInfo(uuid: "GENERATED-SSD", name: "Generated SSD", path: disk.path, totalBytes: 10_000_000_000, freeBytes: 9_000_000_000, isInternal: false, isWritable: true)
        var settings = AppSettings(); settings.selectedVolumeUUID = volume.uuid; try store.save(settings)
    }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at: root) } }
    func tool(_ id: String) throws -> CacheDescriptor { try XCTUnwrap(CacheCatalog.find(id, home: home)) }
    func nativeStatus(_ descriptor: CacheDescriptor, state: String = "native-available") -> AdapterStatus {
        AdapterStatus(toolID: descriptor.id, adapterVersion: CacheAdapters.version, version: "999.0.0", effectiveCachePath: nil, state: state, explanation: "Generated policy fixture", canReleaseSource: false)
    }
    func engine(configurationCheckpoint: @escaping (ConfigurationChange) throws -> Void = { _ in }) -> MigrationEngine {
        MigrationEngine(store: store, home: home, volumeProvider: { _ in self.volume }, verifyNative: false, busyCheck: { _, _ in [] }, adapterInspector: { self.nativeStatus($0) }, configurationCheckpoint: configurationCheckpoint)
    }
    func put(_ path: URL, _ text: String = "generated content") throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: path)
    }

    func testExpandedCatalogSeparatesCachePayloadsAndKeepsLinkedOrigins() throws {
        XCTAssertEqual(Set(CacheCatalog.all(home: home).map(\.id)), ["npm", "bun", "cocoapods", "pip", "homebrew", "gradle", "uv", "yarn", "go", "ccache"])
        let yarn = try tool("yarn")
        XCTAssertEqual(yarn.destinationChild, "v6"); XCTAssertEqual(yarn.environmentKey, "YARN_CACHE_FOLDER")
        XCTAssertFalse(yarn.canReleaseLocal)
        XCTAssertEqual(try tool("go").source.lastPathComponent, "go-build")
        XCTAssertTrue(try tool("ccache").canReleaseLocal)
        try put(try tool("ccache").source.appendingPathComponent("ccache.conf"), "max_size = 5G")
        XCTAssertFalse(try tool("ccache").canReleaseLocal)
    }
    func testCcacheRecognizesLegacySourceWithoutCreatingEitherCache() throws {
        let legacy = home.appendingPathComponent(".ccache")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        XCTAssertEqual(try tool("ccache").source.path, legacy.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Caches/ccache").path))
    }
    func testUnqualifiedVersionsAndYarnNeverReleaseSource() throws {
        for id in ["yarn", "go", "ccache"] {
            let descriptor = try tool(id), expected = descriptor.destinationChild.isEmpty ? descriptor.source : descriptor.source.deletingLastPathComponent()
            XCTAssertFalse(CacheAdapters.assess(descriptor, version: "999.0.0", effectiveRoot: expected.path, custom: false, queried: true).canReleaseSource)
        }
    }
    func testYarnDiscoveryDoesNotCreateAbsentUserCache() throws {
        let descriptor = try tool("yarn")
        _ = CacheAdapters.inspect(descriptor, home: home, directory: home)
        XCTAssertFalse(FileManager.default.fileExists(atPath: descriptor.source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: descriptor.source.deletingLastPathComponent().path))
    }
    func testGoDiscoveryDoesNotCreateAbsentCacheOrTelemetryConfiguration() throws {
        _ = CacheAdapters.inspect(try tool("go"), home: home, directory: home)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: home.path).isEmpty)
    }
    func testGoAndCcacheConfigurationTakesPrecedence() throws {
        let goConfig = home.appendingPathComponent("Library/Application Support/go/env")
        try put(goConfig, "GOCACHE=/generated/custom\n")
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "go", directory: home, home: home, processEnvironment: [:]))
        try FileManager.default.removeItem(at: goConfig)
        XCTAssertFalse(CacheRouter.hasCustomPreference(toolID: "go", directory: home, home: home, processEnvironment: [:]))
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "go", directory: home, home: home, processEnvironment: ["GOENV": "off"]))
        try put(home.appendingPathComponent("Library/Preferences/ccache/ccache.conf"), "cache_dir = /generated/custom\n")
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "ccache", directory: home, home: home, processEnvironment: [:]))
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "ccache", directory: home, home: home, processEnvironment: ["CCACHE_CONFIGPATH": "/generated/config"]))
    }
    func testExplicitExpandedCommandConfigurationIsNotOverridden() {
        for argument in ["--cache-folder=/generated", "--use-yarnrc=/generated", "--cwd=/generated", "--enable-pnp", "YARN_CACHE_FOLDER=/generated"] {
            XCTAssertTrue(CacheRouter.commandExclusions(["yarn", argument]).contains("yarn"), argument)
        }
        for argument in ["-C", "-C=/generated", "GOCACHE=/generated", "GOENV=/generated"] { XCTAssertTrue(CacheRouter.commandExclusions(["go", argument]).contains("go"), argument) }
        for argument in ["--dir=/generated", "--config-path=/generated", "-d/generated", "-o", "cache_dir=/generated", "CCACHE_CONFIGPATH=/generated"] { XCTAssertTrue(CacheRouter.commandExclusions(["ccache", argument]).contains("ccache"), argument) }
        XCTAssertTrue(CacheRouter.commandExclusions(["go", "build", "./..."]).isEmpty)
    }
    func testYarnGlobalConfigurationAndSelectorsArePreserved() throws {
        let global = root.appendingPathComponent("global-yarnrc")
        try put(global, "cache-folder /generated/custom\n")
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "yarn", directory: home, home: home, processEnvironment: [:], yarnGlobalConfigurations: [global]))
        for key in ["YARN_CONFIG", "YARN_RC_FILENAME", "PREFIX", "DESTDIR", "XDG_CONFIG_HOME"] {
            XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "yarn", directory: home, home: home, processEnvironment: [key: "/generated/custom"], yarnGlobalConfigurations: []))
        }
    }
    func testCcachePreservesAnyUserAndAncestorConfiguration() throws {
        let project = home.appendingPathComponent("Documents/project/nested")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        for path in [home.appendingPathComponent("Library/Preferences/ccache/ccache.conf"), project.deletingLastPathComponent().appendingPathComponent("ccache.conf")] {
            try put(path, "compiler_check = content\n")
            XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "ccache", directory: project, home: home, processEnvironment: [:]))
            try FileManager.default.removeItem(at: path)
        }
    }
    func testFutureCacheWithMissingSourceCreatesOnlyExternalDestinationAndJournal() throws {
        let descriptor = try tool("go")
        let record = try engine().prepareFutureCache(toolID: descriptor.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: descriptor.source.path))
        let location = try XCTUnwrap(store.settings().locations[descriptor.id])
        XCTAssertEqual(location.logicalBytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: disk.appendingPathComponent(location.relativePath).path))
        XCTAssertFalse(store.settings().shellIntegrationEnabled)
        XCTAssertNil(record.measuredFreeDelta)
        XCTAssertTrue(store.pendingConfigurationRecords().isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.base.path).filter { $0.hasPrefix("configuration-") }
        let change = try store.read(ConfigurationChange.self, name: XCTUnwrap(names.first))
        XCTAssertEqual(change.state, "completed")
        XCTAssertEqual(change.source, store.base.appendingPathComponent("settings.json").path)
        XCTAssertNotEqual(change.before, change.after)
        XCTAssertEqual(CacheRouter.decisions(settings: store.settings(), volumes: [volume]).first { $0.toolID == descriptor.id }?.mode, "ssd")
        XCTAssertEqual(CacheRouter.decisions(settings: store.settings(), volumes: []).first { $0.toolID == descriptor.id }?.mode, "local")
    }
    func testFutureYarnCacheCreatesVersionedPayloadButNoLocalOrigin() throws {
        _ = try engine().prepareFutureCache(toolID: "yarn")
        let location = try XCTUnwrap(store.settings().locations["yarn"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: disk.appendingPathComponent(location.relativePath).appendingPathComponent("v6").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try tool("yarn").source.path))
    }
    func testFutureConfigurationRejectsFilledSourceAndExistingDestination() throws {
        let descriptor = try tool("go")
        try put(descriptor.source.appendingPathComponent("result"))
        XCTAssertThrowsError(try engine().prepareFutureCache(toolID: descriptor.id))
        XCTAssertNil(store.settings().locations[descriptor.id])
        try FileManager.default.removeItem(at: descriptor.source)
        _ = try engine().prepareFutureCache(toolID: descriptor.id)
        let original = try XCTUnwrap(store.settings().locations[descriptor.id])
        XCTAssertThrowsError(try engine().prepareFutureCache(toolID: descriptor.id))
        XCTAssertEqual(store.settings().locations[descriptor.id]?.relativePath, original.relativePath)
    }
    func testFutureConfigurationRefusesUnsupportedToolsBeforeCreatingDestination() throws {
        let engine = MigrationEngine(store: store, home: home, volumeProvider: { _ in self.volume }, verifyNative: false, busyCheck: { _, _ in [] }, adapterInspector: { self.nativeStatus($0, state: "missing-tool") })
        XCTAssertThrowsError(try engine.prepareFutureCache(toolID: "go"))
        XCTAssertTrue(store.settings().locations.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: disk.path).isEmpty)
    }
    func testInterruptedConfigurationPreservesPreviousSettingsAndPendingEvidence() throws {
        enum Interruption: Error { case simulated }
        let previous = try Data(contentsOf: store.base.appendingPathComponent("settings.json"))
        let operation = engine(configurationCheckpoint: { change in if change.state == "prepared" { throw Interruption.simulated } })
        XCTAssertThrowsError(try operation.prepareFutureCache(toolID: "go"))
        XCTAssertEqual(try Data(contentsOf: store.base.appendingPathComponent("settings.json")), previous)
        XCTAssertEqual(store.pendingConfigurationRecords().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try tool("go").source.path))
        XCTAssertThrowsError(try engine().prepareFutureCache(toolID: "ccache"))
    }
    func testPreparedDestinationCannotFollowReplacedAncestorOutsideSSD() throws {
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let operation = engine(configurationCheckpoint: { change in
            if change.state == "prepared" { try FileManager.default.createSymbolicLink(at: self.disk.appendingPathComponent("MacCaches"), withDestinationURL: outside) }
        })
        XCTAssertThrowsError(try operation.prepareFutureCache(toolID: "go"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        XCTAssertNil(store.settings().locations["go"])
        XCTAssertEqual(store.pendingConfigurationRecords().count, 1)
    }
    func testPreparedSettingsCannotFollowReplacementLinkWithIdenticalContents() throws {
        let settingsURL = store.base.appendingPathComponent("settings.json"), outside = root.appendingPathComponent("outside-settings")
        let original = try Data(contentsOf: settingsURL); try original.write(to: outside)
        let operation = engine(configurationCheckpoint: { change in
            if change.state == "prepared" {
                try FileManager.default.removeItem(at: settingsURL)
                try FileManager.default.createSymbolicLink(at: settingsURL, withDestinationURL: outside)
            }
        })
        XCTAssertThrowsError(try operation.prepareFutureCache(toolID: "go"))
        XCTAssertEqual(try Data(contentsOf: outside), original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: settingsURL.path), outside.path)
        XCTAssertEqual(store.pendingConfigurationRecords().count, 1)
    }
    func testFutureConfigurationRefusesFIFOWithoutBlockingOrReplacingIt() throws {
        let settings = store.base.appendingPathComponent("settings.json")
        try FileManager.default.removeItem(at: settings)
        XCTAssertEqual(mkfifo(settings.path, 0o600), 0)
        let start = Date()
        XCTAssertThrowsError(try engine().prepareFutureCache(toolID: "go"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        var metadata = stat(); XCTAssertEqual(lstat(settings.path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & S_IFMT, mode_t(S_IFIFO))
    }
    func testFutureConfigurationPreservesOversizedSettings() throws {
        let settings = store.base.appendingPathComponent("settings.json")
        let oversized = Data(repeating: 65, count: 4_194_305)
        try oversized.write(to: settings)
        XCTAssertThrowsError(try engine().prepareFutureCache(toolID: "go"))
        XCTAssertEqual(try Data(contentsOf: settings), oversized)
        XCTAssertTrue(store.pendingConfigurationRecords().isEmpty)
    }
    func testCancellationAndBusyToolDoNotConfigureFutureCache() throws {
        let cancellation = CancellationFlag(); cancellation.cancel()
        XCTAssertThrowsError(try engine().prepareFutureCache(toolID: "go", cancellation: cancellation))
        let busy = MigrationEngine(store: store, home: home, volumeProvider: { _ in self.volume }, verifyNative: false, busyCheck: { _, _ in [BusyProcess(pid: 999, name: "Generated writer")] }, adapterInspector: { self.nativeStatus($0) })
        XCTAssertThrowsError(try busy.prepareFutureCache(toolID: "go"))
        XCTAssertTrue(store.settings().locations.isEmpty)
        XCTAssertTrue(store.pendingConfigurationRecords().isEmpty)
    }
    func testFutureConfigurationUsesSharedLease() throws {
        let lease = try OperationLease(store: store)
        XCTAssertThrowsError(try engine().prepareFutureCache(toolID: "go"))
        withExtendedLifetime(lease) {}
        XCTAssertTrue(store.settings().locations.isEmpty)
    }
    func testYarnCopyRetainsOriginEvenWhenReleaseRequestedInFixture() throws {
        let descriptor = try tool("yarn")
        let original = descriptor.source.appendingPathComponent("package/result")
        try put(original)
        _ = try engine().migrate(toolID: descriptor.id, removeLocal: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        let location = try XCTUnwrap(store.settings().locations[descriptor.id])
        XCTAssertEqual(try Data(contentsOf: disk.appendingPathComponent(location.relativePath).appendingPathComponent("v6/package/result")), try Data(contentsOf: original))
    }
    func testShellRestoresExpandedKeysAndHonorsExplicitCommandSelectors() throws {
        let helper = root.appendingPathComponent("helper")
        try Data("#!/bin/sh\nprintf 'YARN_CACHE_FOLDER\\t/generated/yarn\\nGOCACHE\\t/generated/go\\nCCACHE_DIR\\t/generated/ccache\\n'\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        try ShellIntegration.install(helper: helper, store: store, home: home)
        XCTAssertTrue(ShellIntegration.isCurrent(store: store))
        let script = "source '\(store.base.appendingPathComponent("integration.zsh").path)'; _cachessd_route 'go -C /generated build'; print -r -- \"go=${GOCACHE-unset};ccache=${CCACHE_DIR-unset}\"; _cachessd_route 'yarn --enable-pnp install'; print -r -- \"yarn=${YARN_CACHE_FOLDER-unset};go=${GOCACHE-unset}\"; _cachessd_route 'ccache --dir=/custom clang'; print -r -- \"ccache=${CCACHE_DIR-unset}\""
        let result = try CommandRunner.run(URL(fileURLWithPath: "/bin/zsh"), ["-c", script], environment: ["HOME": home.path, "PATH": "/usr/bin:/bin"])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("go=unset;ccache=/generated/ccache"), result.output)
        XCTAssertTrue(result.output.contains("yarn=unset;go=/generated/go"), result.output)
        XCTAssertTrue(result.output.contains("ccache=unset"), result.output)
    }
    func testLegacyAndUnreadableRoutingScriptsRequireReviewedRefresh() throws {
        XCTAssertFalse(ShellIntegration.isCurrent(store: store))
        let script = store.base.appendingPathComponent("integration.zsh")
        try Data("# CacheSSD legacy seven-key integration\n".utf8).write(to: script)
        XCTAssertFalse(ShellIntegration.isCurrent(store: store))
        try Data("# CacheSSD routing version: 2\n".utf8).write(to: script)
        XCTAssertTrue(ShellIntegration.isCurrent(store: store))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: script.path)
        XCTAssertFalse(ShellIntegration.isCurrent(store: store))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: script.path)
    }
}
