import Foundation
import Darwin

public struct AcceptanceCheck: Codable, Sendable {
    public let id: String
    public let status: String
}

/// Portable, privacy-minimized evidence. Automated checks never attest human gates.
public struct AcceptanceReport: Codable, Sendable {
    public let schemaVersion: Int
    public let suite: String
    public let startedAt: Date
    public let finishedAt: Date
    public let macOS: String
    public let architecture: String
    public let helperSHA256: String
    public let scope: String
    public let checks: [AcceptanceCheck]
    public let fixtureDisposition: String
    public let pendingManualGates: [String]
    public let passed: Bool

    /// Create only a new private report; never follow links or overwrite evidence.
    public func write(to output: URL) throws {
        let parent = output.deletingLastPathComponent().standardizedFileURL
        guard Paths.physicalURL(parent).standardizedFileURL.path == parent.path else { throw AcceptanceRunner.failure() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(self)
        let fd = open(output.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AcceptanceRunner.failure() }
        var completed = false
        defer { close(fd); if !completed { try? FileManager.default.removeItem(at: output) } }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        try file.write(contentsOf: bytes); try file.synchronize(); completed = true
    }
}

public enum AcceptanceRunner {
    static let checkIDs = ["bundled-resources-pt-en", "indexed-explorer", "personal-copy-recovery", "cache-copy-restore-local-fallback", "isolated-shell-disable"]
    static let manualGates = ["second-mac-human-acceptance", "voiceover-keyboard-pt-en", "developer-id-notarization", "signed-update-accept-reject", "physical-cable-power-faults", "ten-person-seven-day-beta"]
    static func failure() -> Error { CacheSSDError.message("DiskWing acceptance check could not complete safely. Use an existing, writable, unlinked fixture directory and a new report filename.") }

    public static func run(workspace: URL, helper: URL) throws -> AcceptanceReport {
        try run(workspace: workspace, helper: helper, beforeCheck: { _ in })
    }

    // Internal fault boundary allows tests to verify report failure/fixture retention.
    static func run(workspace: URL, helper: URL, beforeCheck: (String) throws -> Void, onFailure: (String, Error) -> Void = { _, _ in }) throws -> AcceptanceReport {
        let fm = FileManager.default, parent = Paths.physicalURL(workspace)
        var info = stat()
        guard parent.standardizedFileURL.path == workspace.standardizedFileURL.path,
              lstat(parent.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw CacheSSDError.message("Acceptance requires an existing fixture directory without custom links.") }
        guard fm.isWritableFile(atPath: parent.path) else { throw CacheSSDError.message("The acceptance fixture directory is not writable.") }
        guard Volumes.free(at: parent) > 1_073_741_824 else { throw CacheSSDError.message("Acceptance requires at least 1 GiB of available fixture space.") }
        guard fm.isExecutableFile(atPath: helper.path) else { throw CacheSSDError.message("The acceptance helper is not executable.") }
        try FileTree.validateDestination(parent)
        let helperHash = try FileTree.hash(helper)
        let root = parent.appendingPathComponent(".DiskWing-acceptance-\(UUID().uuidString)")
        guard mkdir(root.path, 0o700) == 0 else { throw failure() }
        // Keep SQLite on physical paths (NOFOLLOW), but give the injected home
        // Foundation's stable directory spelling before deriving absent sources.
        let homePath = root.appendingPathComponent("home")
        try fm.createDirectory(at: homePath, withIntermediateDirectories: false)
        let started = Date(), home = URL(fileURLWithPath: homePath.path, isDirectory: true).standardizedFileURL, store = Store(base: root.appendingPathComponent("support"))
        let previousLanguage = L10n.preference
        defer { L10n.preference = previousLanguage }
        var checks: [AcceptanceCheck] = [], failed = false
        for id in checkIDs {
            if failed { checks.append(AcceptanceCheck(id: id, status: "not-run")); continue }
            do {
                try beforeCheck(id)
                switch id {
                case "bundled-resources-pt-en":
                    L10n.preference = "en"; try require(L10n.text("Nome") == "Name" && CacheAdapters.qualifiedVersions.count == 7)
                    L10n.preference = "pt-BR"; try require(L10n.text("Nome") == "Nome")
                case "indexed-explorer":
                    let source = home.appendingPathComponent("Downloads/sample/nested")
                    try fm.createDirectory(at: source, withIntermediateDirectories: true)
                    try Data("generated sample".utf8).write(to: source.appendingPathComponent("sample.txt"))
                    let index = try ScanIndex(url: store.base.appendingPathComponent("index.sqlite"))
                    let report = try IndexedScanner(home: home).scan(home.appendingPathComponent("Downloads"), index: index)
                    let result = try index.page(sessionID: report.id, search: "sample.txt")
                    try require(!report.isPartial && result.total == 1 && result.items.first?.name == "sample.txt")
                case "personal-copy-recovery":
                    let source = home.appendingPathComponent("Downloads/sample"), destination = root.appendingPathComponent("personal-destination")
                    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                    let expected = try FileTree.digest(source, workspace: root)
                    let actions = PersonalActions(home: home, store: store, trashHandler: { item in
                        let trash = root.appendingPathComponent("fixture-trash")
                        try fm.moveItem(at: item, to: trash); return trash
                    }, checkpoint: { if $0.phase == .completed { throw failure() } })
                    var interrupted = false
                    do { _ = try actions.move(source, to: destination) } catch { interrupted = true }
                    try require(interrupted && !fm.fileExists(atPath: source.path))
                    guard let journal = store.operations().first(where: { $0.kind == "personalMove" }) else { throw failure() }
                    // Preserve the simulated Trash original; recover from the verified copy.
                    try fm.moveItem(at: root.appendingPathComponent("fixture-trash"), to: root.appendingPathComponent("preserved-original"))
                    try RecoveryManager(store: store, home: home).restoreSource(id: journal.id)
                    try require(try FileTree.digest(source, workspace: root) == expected)
                    try require(try FileTree.digest(destination.appendingPathComponent("sample"), workspace: root) == expected)
                case "cache-copy-restore-local-fallback":
                    guard let tool = CacheCatalog.find("npm", home: home) else { throw failure() }
                    try fm.createDirectory(at: tool.source, withIntermediateDirectories: true)
                    try Data("generated cache payload; no native install".utf8).write(to: tool.source.appendingPathComponent("artifact"))
                    let expected = try FileTree.digest(tool.source, workspace: root), disk = root.appendingPathComponent("simulated-volume")
                    try fm.createDirectory(at: disk, withIntermediateDirectories: true)
                    let volume = VolumeInfo(uuid: "GENERATED-ACCEPTANCE-VOLUME", name: "Generated", path: disk.path, totalBytes: Volumes.free(at: parent), freeBytes: Volumes.free(at: parent), isInternal: false, isWritable: true)
                    var settings = store.settings(); settings.selectedVolumeUUID = volume.uuid; try store.save(settings)
                    let engine = MigrationEngine(store: store, home: home, volumeProvider: { _ in volume }, verifyNative: false)
                    _ = try engine.migrate(toolID: "npm", removeLocal: false)
                    try require(try FileTree.digest(tool.source, workspace: root) == expected)
                    try require(CacheRouter.decisions(settings: store.settings(), volumes: [volume]).first(where: { $0.toolID == "npm" })?.mode == "ssd")
                    try require(CacheRouter.decisions(settings: store.settings(), volumes: []).allSatisfy { $0.mode == "local" })
                    try fm.moveItem(at: tool.source, to: root.appendingPathComponent("preserved-cache-original"))
                    try engine.restore(toolID: "npm")
                    try require(try FileTree.digest(tool.source, workspace: root) == expected)
                    try require(store.settings().locations["npm"] == nil)
                case "isolated-shell-disable":
                    let rc = home.appendingPathComponent(".zshrc"), original = "export DISKWING_GENERATED_FIXTURE=1\n"
                    try Data(original.utf8).write(to: rc)
                    try ShellIntegration.install(helper: helper, store: store, home: home)
                    try require(store.settings().shellIntegrationEnabled)
                    try ShellIntegration.uninstall(store: store, home: home)
                    let text = try String(contentsOf: rc, encoding: .utf8)
                    try require(text.contains(original) && !text.contains("CacheSSD managed integration") && !store.settings().shellIntegrationEnabled && !store.settings().useExternal)
                    try require(try Data(contentsOf: store.base.appendingPathComponent("zshrc-before-cachessd.txt")) == Data(original.utf8))
                default: throw failure()
                }
                checks.append(AcceptanceCheck(id: id, status: "passed"))
            } catch {
                // Raw errors can contain file paths. Keep them out of the portable report.
                onFailure(id, error)
                checks.append(AcceptanceCheck(id: id, status: "failed")); failed = true
            }
        }
        var disposition = "retained-for-review"
        if !failed {
            do { try fm.removeItem(at: root); disposition = "removed" }
            catch { disposition = "cleanup-failed" }
        }
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "other"
        #endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return AcceptanceReport(schemaVersion: 1, suite: "diskwing-portable-acceptance-v1", startedAt: started, finishedAt: Date(), macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)", architecture: architecture, helperSHA256: helperHash, scope: "Generated fixtures; same-volume simulated SSD and Trash; no native tools, GUI, network, mounts or personal data", checks: checks, fixtureDisposition: disposition, pendingManualGates: manualGates, passed: !failed && disposition == "removed")
    }
    private static func require(_ value: Bool) throws { if !value { throw failure() } }
}
