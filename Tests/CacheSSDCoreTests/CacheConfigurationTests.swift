import XCTest
@testable import CacheSSDCore

final class CacheConfigurationTests: XCTestCase {
    var root: URL!
    var home: URL!
    override func setUpWithError() throws {
        let base = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = Paths.physicalURL(base).appendingPathComponent("DiskWing-config-test-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at:home,withIntermediateDirectories:true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }
    func custom(_ env: [String:String] = [:], globals: [URL] = []) -> Bool {
        CacheRouter.hasCustomPreference(toolID:"npm",directory:home,home:home,processEnvironment:env,npmGlobalConfigurations:globals)
    }
    func testNpmEnvironmentConfigurationSelectorsAlwaysTakePrecedence() {
        for key in ["npm_config_userconfig","NPM_CONFIG_GLOBALCONFIG","NPM_CONFIG_PREFIX","NPM_CONFIG_CACHE"] { XCTAssertTrue(custom([key:"/generated/custom"])) }
        XCTAssertFalse(custom())
    }
    func testFilesystemRootRepresentationsTerminateConfigurationDiscovery() throws {
        for directory in [URL(fileURLWithPath: "/", isDirectory: true), try XCTUnwrap(URL(string: "file://localhost/"))] {
            XCTAssertFalse(CacheRouter.hasCustomPreference(toolID: "pip", directory: directory, home: home, processEnvironment: [:], pipGlobalConfigurations: []))
        }
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID: "pip", directory: try XCTUnwrap(URL(string: "https://example.invalid/")), home: home, processEnvironment: [:], pipGlobalConfigurations: []))
    }
    func testUnvisitedDeepAncestorsCannotBeAssumedDefault() throws {
        var directory = root.appendingPathComponent("project")
        for _ in 0..<45 { directory.appendPathComponent("nested") }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID:"npm",directory:directory,home:home,processEnvironment:[:],npmGlobalConfigurations:[]))
    }
    func testGlobalCacheAndIndirectConfigurationArePreserved() throws {
        let file = root.appendingPathComponent("npmrc")
        for setting in ["cache=/generated/cache","userconfig=/generated/other","globalconfig=/generated/other","prefix=/generated/prefix"] {
            try Data(setting.utf8).write(to:file)
            XCTAssertTrue(custom(globals:[file]))
        }
        try Data("registry=https://registry.npmjs.org\n".utf8).write(to:file)
        XCTAssertFalse(custom(globals:[file]))
    }
    func testInvalidLinkedOrOversizedConfigurationIsNotAssumedDefault() throws {
        let file = root.appendingPathComponent("npmrc"), link = root.appendingPathComponent("link")
        try Data([0xff,0xfe]).write(to:file)
        XCTAssertTrue(custom(globals:[file]))
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:file)
        XCTAssertTrue(custom(globals:[link]))
        try Data(repeating:65,count:1_048_577).write(to:file)
        XCTAssertTrue(custom(globals:[file]))
    }
    func testDivergentUnknownAndUnqualifiedNativePathsCannotReleaseSource() throws {
        let npm = try XCTUnwrap(CacheCatalog.find("npm",home:home)), version = CacheAdapters.qualifiedVersions["npm"]
        let expected = npm.source.deletingLastPathComponent().path
        XCTAssertTrue(CacheAdapters.assess(npm,version:version,effectiveRoot:expected,custom:false,queried:true).canReleaseSource)
        XCTAssertFalse(CacheAdapters.assess(npm,version:version,effectiveRoot:"/generated/other",custom:false,queried:true).canReleaseSource)
        XCTAssertEqual(CacheAdapters.assess(npm,version:version,effectiveRoot:nil,custom:false,queried:true).state,"configuration-unverified")
        XCTAssertFalse(CacheAdapters.assess(npm,version:"999.0.0",effectiveRoot:expected,custom:false,queried:true).canReleaseSource)
        XCTAssertFalse(CacheAdapters.assess(npm,version:version,effectiveRoot:expected,custom:true,queried:true).canReleaseSource)
        XCTAssertFalse(CacheAdapters.assess(npm,version:version,effectiveRoot:expected,custom:false,queried:false).canReleaseSource)
    }
    func testPipGlobalsAndXDGSelectorsPreserveConfiguration() throws {
        let file = root.appendingPathComponent("pip.conf")
        try Data("[global]\ncache-dir=/generated/custom\n".utf8).write(to:file)
        XCTAssertTrue(CacheRouter.hasCustomPreference(toolID:"pip",directory:home,home:home,processEnvironment:[:],pipGlobalConfigurations:[file]))
        for key in ["PIP_CONFIG_FILE","XDG_CONFIG_HOME","XDG_DATA_HOME","XDG_DATA_DIRS"] {
            XCTAssertTrue(CacheRouter.hasCustomPreference(toolID:"pip",directory:home,home:home,processEnvironment:[key:"generated"],pipGlobalConfigurations:[]))
        }
        XCTAssertFalse(CacheRouter.hasCustomPreference(toolID:"pip",directory:home,home:home,processEnvironment:[:],pipGlobalConfigurations:[]))
    }
    func testUnsupportedDiscoveryAndLinkedInstallToolsPreserveOriginal() throws {
        for id in ["cocoapods","gradle","bun","uv"] {
            let tool = try XCTUnwrap(CacheCatalog.find(id,home:home))
            XCTAssertFalse(CacheAdapters.assess(tool,version:CacheAdapters.qualifiedVersions[id],effectiveRoot:nil,custom:false,queried:false).canReleaseSource)
        }
    }
    func testCommandSelectorsOmitOnlyAffectedTools() {
        XCTAssertEqual(CacheRouter.commandExclusions(["npm","--userconfig","fixture"]),["npm"])
        XCTAssertEqual(CacheRouter.commandExclusions(["--globalconfig=fixture","--link-mode=copy"]),["npm","uv"])
        XCTAssertEqual(CacheRouter.commandExclusions(["--backend=copyfile","-C","fixture"]),["npm","bun"])
        for arg in ["--userconf=fixture","--globalconf=fixture","--pref=fixture","--ca=fixture","-gCfixture"] { XCTAssertTrue(CacheRouter.commandExclusions(["npm",arg]).contains("npm")) }
        XCTAssertFalse(CacheRouter.commandExclusions(["npm","--offline","--ignore-scripts"]).contains("npm"))
        XCTAssertTrue(CacheRouter.commandExclusions(["npm","install","sample"]).isEmpty)
    }
    func testShellHookPassesOmitFlagForExplicitCommandConfiguration() throws {
        let helper = root.appendingPathComponent("fixture-helper"), log = root.appendingPathComponent("args.txt")
        let script = "#!/bin/sh\nprintf '%s\\n' \"$@\" >> '\(log.path)'\n"
        try Data(script.utf8).write(to:helper)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:helper.path)
        let store = Store(base:root.appendingPathComponent("support"))
        try ShellIntegration.install(helper:helper,store:store,home:home)
        let integration = store.base.appendingPathComponent("integration.zsh")
        let commands = "source '\(integration.path)'; : > '\(log.path)'; _cachessd_route 'npm --userconf=sample install'; _cachessd_route 'npm -gCsample install'; _cachessd_route 'NPM_CONFIG_GLOBALCONFIG=sample npm install'; _cachessd_route 'npm install --offline --ignore-scripts'; _cachessd_route 'npm \"--userconf=sample\" install'; _cachessd_route 'npm exec --package=sample --offline'"
        let result = try CommandRunner.run(URL(fileURLWithPath:"/bin/zsh"),["-c",commands],environment:["PATH":"/usr/bin:/bin","HOME":home.path])
        XCTAssertEqual(result.status,0,result.output)
        XCTAssertEqual(try String(contentsOf:log).components(separatedBy:"--omit-npm").count-1,4)
    }
    func testRoutingDoesNotReplaceGlobalOrSelectedConfiguration() throws {
        let disk = root.appendingPathComponent("volume"), data = disk.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at:data,withIntermediateDirectories:true)
        let volume = VolumeInfo(uuid:"GENERATED",name:"Generated",path:disk.path,totalBytes:1_000_000_000,freeBytes:900_000_000,isInternal:false,isWritable:true)
        var settings = AppSettings(); settings.useExternal = true
        settings.locations["npm"] = CacheLocation(toolID:"npm",volumeUUID:volume.uuid,relativePath:"cache",migratedAt:Date(),logicalBytes:1)
        XCTAssertNotNil(CacheRouter.environment(settings:settings,directory:home,volumes:[volume],home:home,processEnvironment:[:],npmGlobalConfigurations:[])["npm_config_cache"])
        XCTAssertNil(CacheRouter.environment(settings:settings,directory:home,volumes:[volume],home:home,processEnvironment:["NPM_CONFIG_USERCONFIG":"fixture"],npmGlobalConfigurations:[])["npm_config_cache"])
    }
}
