import XCTest
import Foundation
@testable import CacheSSDCore

/// Opt-in: small pinned public artifacts, disposable homes/caches/projects, no install hooks.
final class NativeWorkflowTests: XCTestCase {
    var root: URL!
    var home: URL!
    var project: URL!
    var disk: URL!
    var store: Store!
    var environment: [String: String]!
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["DISKWING_RUN_INSTALL_TESTS"] == "1" else { throw XCTSkip("Set DISKWING_RUN_INSTALL_TESTS=1 for real disposable native workflows") }
        let parent = ProcessInfo.processInfo.environment["CACHESSD_TEST_TEMP"].map(URL.init(fileURLWithPath:)) ?? FileManager.default.temporaryDirectory
        root = parent.appendingPathComponent("DiskWing-native-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); root = Paths.physicalURL(root)
        home = root.appendingPathComponent("home"); project = root.appendingPathComponent("project"); disk = root.appendingPathComponent("SSD")
        for directory in [home!,project!,disk!,root.appendingPathComponent("tmp")] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        store = Store(base: root.appendingPathComponent("support"))
        var bins = ["/opt/homebrew/bin","/usr/local/bin","/usr/bin","/bin","/usr/sbin","/sbin"]
        for name in ["node","ruby","bun","uv","python3"] { if let executable = ToolLocator.locate(name) { bins.insert(executable.deletingLastPathComponent().path, at: 0) } }
        // Never pass host tokens, SSH sockets, registry auth, or user config into these projects.
        environment = ["PATH":bins.joined(separator:":"),"HOME":home.path,"TMPDIR":root.appendingPathComponent("tmp").path,
                       "LANG":"en_US.UTF-8","LC_ALL":"en_US.UTF-8","CI":"1","NPM_CONFIG_USERCONFIG":"/dev/null",
                       "npm_config_registry":"https://registry.npmjs.org","PIP_CONFIG_FILE":"/dev/null","PIP_DISABLE_PIP_VERSION_CHECK":"1",
                       "HOMEBREW_NO_AUTO_UPDATE":"1","HOMEBREW_NO_ANALYTICS":"1","HOMEBREW_NO_ENV_HINTS":"1",
                       "CP_HOME_DIR":home.appendingPathComponent(".cocoapods").path,"COCOAPODS_DISABLE_STATS":"true",
                       "UV_PYTHON_DOWNLOADS":"never","UV_LINK_MODE":"copy"]
        if let java = try? CommandRunner.run(URL(fileURLWithPath:"/usr/libexec/java_home"),[],timeout:10), java.status == 0 {
            environment["JAVA_HOME"] = java.output.trimmingCharacters(in:.whitespacesAndNewlines)
        }
    }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at: root) } }
    func executable(_ name: String) throws -> URL { try XCTUnwrap(ToolLocator.locate(name),"Required tool missing: \(name)") }
    @discardableResult func run(_ executable: URL, _ args: [String], env: [String:String]? = nil, success: Bool = true) throws -> CommandResult {
        var values = env ?? environment!
        values["PATH"] = executable.deletingLastPathComponent().path + ":" + (values["PATH"] ?? "")
        let result = try CommandRunner.run(executable,args,environment:values,timeout:240,directory:project,maxOutputBytes:524_288)
        if success, result.status != 0 { throw CacheSSDError.message("Native fixture failed (\(executable.lastPathComponent), \(result.status)): " + result.output.suffix(3000)) }
        return result
    }
    func source(_ id: String) throws -> CacheDescriptor {
        let tool = try XCTUnwrap(CacheCatalog.find(id,home:home))
        try FileManager.default.createDirectory(at: tool.source, withIntermediateDirectories:true)
        environment[tool.environmentKey] = tool.destinationChild.isEmpty ? tool.source.path : tool.source.deletingLastPathComponent().path
        return tool
    }
    func migrate(_ tool: CacheDescriptor) throws -> [String:String] {
        let volume = VolumeInfo(uuid:"NATIVE-FIXTURE",name:"Disposable SSD",path:disk.path,totalBytes:1_000_000_000_000,freeBytes:Volumes.free(at:disk),isInternal:false,isWritable:true)
        var settings = AppSettings(); settings.selectedVolumeUUID = volume.uuid; try store.save(settings)
        _ = try MigrationEngine(store:store,home:home,volumeProvider:{ _ in volume },verifyNative:true).migrate(toolID:tool.id,removeLocal:false)
        let route = try XCTUnwrap(CacheRouter.decisions(settings:store.settings(),volumes:[volume]).first { $0.toolID == tool.id })
        XCTAssertEqual(route.mode,"ssd")
        var env = environment!; env[tool.environmentKey] = try XCTUnwrap(route.path)
        let absent = CacheRouter.decisions(settings:store.settings(),volumes:[]).first { $0.toolID == tool.id }
        XCTAssertEqual(absent?.mode,"local"); XCTAssertNil(absent?.path)
        return env
    }
    func reset(_ names: [String]) throws {
        for name in names {
            let item = project.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath:item.path) { try FileManager.default.removeItem(at:item) }
        }
    }
    func record(_ id: String, executable: URL, versionArgs: [String] = ["--version"], offline: String, workflow: String) throws {
        let result = try run(executable,versionArgs)
        let regex = try NSRegularExpression(pattern:#"\b\d+\.\d+(?:\.\d+)?"#)
        let match = regex.firstMatch(in:result.output,range:NSRange(result.output.startIndex...,in:result.output)).flatMap { Range($0.range,in:result.output) }
        let version = match.map { String(result.output[$0]) } ?? "unknown"
        if let output = ProcessInfo.processInfo.environment["DISKWING_NATIVE_REPORT_DIR"] {
            let destination = URL(fileURLWithPath:output)
            try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
            let data: [String:Any] = ["toolID":id,"version":version,"adapterVersion":CacheAdapters.version,"workflow":workflow,"offline":offline,
                                      "sourceRetained":true,"absentVolumeRouting":"local","absentVolumeWorkflow":true,"date":ISO8601DateFormatter().string(from:Date())]
            try JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]).write(to:destination.appendingPathComponent(id+".json"))
        }
    }
    func nodeProject() throws {
        try Data(#"{"private":true,"dependencies":{"is-number":"7.0.0"}}"#.utf8).write(to:project.appendingPathComponent("package.json"))
    }
    func verifyNode() throws {
        _ = try run(executable("node"),["-e","if (!require('./node_modules/is-number')('2')) process.exit(1)"])
    }
    func testNpmActualInstallAndOfflineReuseAfterMigration() throws {
        let tool = try source("npm"), npm = try executable("npm")
        try nodeProject()
        _ = try run(npm,["install","--ignore-scripts","--no-audit","--no-fund"]); try verifyNode()
        let external = try migrate(tool)
        try reset(["node_modules"])
        _ = try run(npm,["install","--offline","--ignore-scripts","--no-audit","--no-fund"],env:external); try verifyNode()
        try reset(["node_modules"])
        _ = try run(npm,["install","--offline","--ignore-scripts","--no-audit","--no-fund"]); try verifyNode()
        try record("npm",executable:npm,offline:"native --offline succeeded",workflow:"pinned package install and execution")
    }
    func testBunActualInstallAndOfflineReuseAfterMigration() throws {
        let tool = try source("bun"), bun = try executable("bun")
        try nodeProject()
        _ = try run(bun,["install","--ignore-scripts"]); try verifyNode()
        let external = try migrate(tool)
        try reset(["node_modules"])
        _ = try run(bun,["install","--offline","--ignore-scripts"],env:external); try verifyNode()
        try reset(["node_modules"])
        _ = try run(bun,["install","--offline","--ignore-scripts"]); try verifyNode()
        try record("bun",executable:bun,offline:"native --offline succeeded",workflow:"pinned package install and execution; original cache retained")
    }
    func testPipActualTargetInstallAndDocumentedOfflineMiss() throws {
        let tool = try source("pip"), python = try executable("python3")
        _ = try run(python,["-m","pip","install","--target","deps","--no-deps","urllib3==2.2.3"])
        _ = try run(python,["-c","import sys;sys.path.insert(0,'deps');import urllib3;assert urllib3.__version__=='2.2.3'"])
        let external = try migrate(tool)
        _ = try run(python,["-m","pip","install","--target","deps-external","--no-deps","urllib3==2.2.3"],env:external)
        let offline = try run(python,["-m","pip","install","--target","deps-offline","--no-index","--no-deps","urllib3==2.2.3"],env:external,success:false)
        XCTAssertNotEqual(offline.status,0,"HTTP cache alone is not an offline wheelhouse")
        _ = try run(python,["-m","pip","install","--target","deps-local","--no-deps","urllib3==2.2.3"])
        try record("pip",executable:python,versionArgs:["-m","pip","--version"],offline:"--no-index miss expected; wheelhouse required",workflow:"isolated --target install and import")
    }
    func testUvActualTargetInstallAndOfflineReuseAfterMigration() throws {
        let tool = try source("uv"), uv = try executable("uv"), python = try executable("python3")
        _ = try run(uv,["pip","install","--python",python.path,"--target","deps","--no-deps","urllib3==2.2.3"])
        let external = try migrate(tool)
        _ = try run(uv,["pip","install","--offline","--python",python.path,"--target","deps-external","--no-deps","urllib3==2.2.3"],env:external)
        _ = try run(python,["-c","import sys;sys.path.insert(0,'deps-external');import urllib3;assert urllib3.__version__=='2.2.3'"])
        _ = try run(uv,["pip","install","--offline","--python",python.path,"--target","deps-local","--no-deps","urllib3==2.2.3"])
        try record("uv",executable:uv,offline:"native --offline succeeded",workflow:"isolated --target install/import in copy mode; original cache retained")
    }
    func testHomebrewBottleFetchAndCacheReuseAfterMigration() throws {
        let tool = try source("homebrew"), brew = try executable("brew")
        _ = try run(brew,["fetch","hello"])
        let external = try migrate(tool)
        _ = try run(brew,["fetch","hello"],env:external)
        _ = try run(brew,["fetch","hello"])
        try record("homebrew",executable:brew,offline:"not established; fetch reuse only",workflow:"bottle download reused; no global formula installation")
    }
    func testCocoaPodsActualTemporaryPodInstallAfterMigration() throws {
        let tool = try source("cocoapods"), pod = try executable("pod")
        try Data("install! 'cocoapods', :integrate_targets => false\nplatform :ios, '13.0'\ntarget 'DiskWingFixture' do\n  pod 'Result', '5.0.0'\nend\n".utf8).write(to:project.appendingPathComponent("Podfile"))
        _ = try run(pod,["install"])
        let external = try migrate(tool)
        try reset(["Pods"])
        _ = try run(pod,["install","--no-repo-update"],env:external)
        XCTAssertTrue(FileManager.default.fileExists(atPath:project.appendingPathComponent("Pods/Result").path))
        try reset(["Pods"])
        _ = try run(pod,["install","--no-repo-update"])
        try record("cocoapods",executable:pod,offline:"not established; cached install without repo update only",workflow:"temporary Podfile install without modifying an Xcode project")
    }
    func testGradleActualJavaBuildAndOfflineReuseAfterMigration() throws {
        let tool = try source("gradle")
        let gradle = try XCTUnwrap(CacheAdapters.gradle(),"Existing Gradle distribution required")
        let wrapper = home.appendingPathComponent(".gradle/wrapper")
        try FileManager.default.createSymbolicLink(at:wrapper,withDestinationURL:FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gradle/wrapper"))
        try Data("rootProject.name = 'diskwing-fixture'\n".utf8).write(to:project.appendingPathComponent("settings.gradle"))
        try Data("plugins { id 'java' }\nrepositories { mavenCentral() }\ndependencies { implementation 'org.apache.commons:commons-lang3:3.14.0' }\n".utf8).write(to:project.appendingPathComponent("build.gradle"))
        let java = project.appendingPathComponent("src/main/java/Fixture.java")
        try FileManager.default.createDirectory(at:java.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("import org.apache.commons.lang3.StringUtils; public class Fixture { public static String value() { return StringUtils.capitalize(\"diskwing\"); } }\n".utf8).write(to:java)
        _ = try run(gradle,["build","--no-daemon","--console=plain"])
        let external = try migrate(tool)
        try reset(["build"])
        _ = try run(gradle,["build","--offline","--no-daemon","--console=plain"],env:external)
        XCTAssertTrue(FileManager.default.fileExists(atPath:project.appendingPathComponent("build/classes/java/main/Fixture.class").path))
        try reset(["build"])
        _ = try run(gradle,["build","--offline","--no-daemon","--console=plain"])
        try record("gradle",executable:gradle,versionArgs:["--version","--no-daemon"],offline:"native --offline build succeeded",workflow:"temporary Java project compiles pinned Maven dependency")
    }
}
