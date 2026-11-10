import Foundation
import AppKit
import Combine
import ServiceManagement
import UserNotifications
import Darwin
import CacheSSDCore

final class SampleAvailability: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true
    var connected: Bool {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
}

@MainActor final class SampleState: ObservableObject {
    enum Change { case volumes, power, preferences }
    var onChange: ((Change) -> Void)?
    let availability = SampleAvailability()
    @Published var volumeConnected = true { didSet { availability.connected = volumeConnected; onChange?(.volumes) } }
    @Published var lowPower = false { didSet { onChange?(.power) } }
    @Published var loginEnabled = false
    @Published var notificationsAllowed = true
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

/// The application has one explicit runtime context. Sample mode cannot create
/// live services, select real files, query native tools, or activate OS settings.
@MainActor final class AppContext {
    let home: URL
    let store: Store
    let helperURL: URL
    let container: URL?
    let samples: SampleState?
    let minimumRescanDelay: TimeInterval
    let minimumRescanInterval: TimeInterval
    var isSamples: Bool { samples != nil }
    var isLowPower: Bool { samples?.lowPower ?? ProcessInfo.processInfo.isLowPowerModeEnabled }
    var loginEnabled: Bool { samples?.loginEnabled ?? (SMAppService.mainApp.status == .enabled) }
    private init(home: URL, store: Store, helper: URL, container: URL?, samples: SampleState?, rescanDelay: TimeInterval = 30, rescanInterval: TimeInterval = 900) {
        self.home = home; self.store = store; helperURL = helper; self.container = container; self.samples = samples
        minimumRescanDelay = rescanDelay; minimumRescanInterval = rescanInterval
    }
    static func live() -> AppContext {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AppContext(home: home, store: Store(base: home.appendingPathComponent("Library/Application Support/CacheSSD")), helper: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/CacheSSDHelper"), container: nil, samples: nil)
    }
    static func forLaunch(arguments: [String], bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> AppContext {
        let flags = arguments.enumerated().filter { $0.element.hasPrefix("--acceptance-") }
        guard !flags.isEmpty else {
            guard bundleIdentifier != "com.cachessd.app.acceptance" else { throw sampleFailure() }
            return live()
        }
        guard bundleIdentifier != "com.cachessd.app" else { throw sampleFailure() }
        guard flags.count == 1, let flag = flags.first, ["--acceptance-workspace", "--acceptance-session"].contains(flag.element), arguments.indices.contains(flag.offset + 1), !arguments[flag.offset + 1].hasPrefix("-") else { throw sampleFailure() }
        let path = URL(fileURLWithPath: arguments[flag.offset + 1])
        return try flag.element == "--acceptance-session" ? resumeSamples(session: path) : makeSamples(workspace: path)
    }
    static func makeSamples(workspace: URL, rescanDelay: TimeInterval = 30, rescanInterval: TimeInterval = 900) throws -> AppContext {
        let parent = Paths.physicalURL(workspace), fm = FileManager.default
        var info = stat()
        guard parent.standardizedFileURL.path == workspace.standardizedFileURL.path,
              lstat(parent.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, fm.isWritableFile(atPath: parent.path),
              Volumes.free(at: parent) > 1_073_741_824 else { throw sampleFailure() }
        try FileTree.validateDestination(parent)
        let root = parent.appendingPathComponent(".DiskWing-samples-\(UUID().uuidString)")
        guard mkdir(root.path, 0o700) == 0 else { throw sampleFailure() }
        // Do not delete failed fixture creation; this directory is owned data
        // for diagnosis, never a reason to clean the supplied parent broadly.
        let physicalHome = root.appendingPathComponent("home")
        try fm.createDirectory(at: physicalHome, withIntermediateDirectories: true)
        let home = URL(fileURLWithPath: physicalHome.path, isDirectory: true).standardizedFileURL
        let downloads = home.appendingPathComponent("Downloads")
        try fm.createDirectory(at: downloads.appendingPathComponent("nested"), withIntermediateDirectories: true)
        for number in 0..<150 { try Data(repeating: 65, count: number + 1).write(to: downloads.appendingPathComponent(String(format: "sample-%03d.txt", number))) }
        try Data("generated searchable sample".utf8).write(to: downloads.appendingPathComponent("nested/find-me.txt"))
        for tool in CacheCatalog.all(home: home) {
            try fm.createDirectory(at: tool.source, withIntermediateDirectories: true)
            try Data("generated cache payload".utf8).write(to: tool.source.appendingPathComponent("fixture-artifact"))
        }
        try fm.createDirectory(at: root.appendingPathComponent("sample-ssd"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("personal-destination"), withIntermediateDirectories: true)
        let helper = root.appendingPathComponent("sample-helper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let store = Store(base: root.appendingPathComponent("support"))
        var settings = AppSettings(); settings.selectedVolumeUUID = "DISKWING-SAMPLE-EXTERNAL"; try store.save(settings)
        var preferences = UserPreferences(); preferences.language = "pt-BR"; try store.write(preferences, name: "preferences.json")
        try Data("diskwing-gui-samples-v1\n".utf8).write(to: root.appendingPathComponent(".diskwing-sample-session"))
        return AppContext(home: home, store: store, helper: helper, container: root, samples: SampleState(), rescanDelay: rescanDelay, rescanInterval: rescanInterval)
    }
    static func resumeSamples(session: URL) throws -> AppContext {
        let root = Paths.physicalURL(session)
        var info = stat()
        guard root.standardizedFileURL.path == session.standardizedFileURL.path, root.lastPathComponent.hasPrefix(".DiskWing-samples-"), UUID(uuidString: String(root.lastPathComponent.dropFirst(".DiskWing-samples-".count))) != nil,
              lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw sampleFailure() }
        let required = [root.appendingPathComponent(".diskwing-sample-session"), root.appendingPathComponent("home"), root.appendingPathComponent("support"), root.appendingPathComponent("sample-helper")]
        for url in required {
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT != S_IFLNK else { throw sampleFailure() }
        }
        for url in [required[0], required[3]] { guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw sampleFailure() } }
        for url in [required[1], required[2]] { guard (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { throw sampleFailure() } }
        if let files = FileManager.default.enumerator(at: required[2], includingPropertiesForKeys: nil) {
            for case let file as URL in files { guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT != S_IFLNK else { throw sampleFailure() } }
        } else { throw sampleFailure() }
        guard ((try required[0].resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0) <= 64 else { throw sampleFailure() }
        guard try Data(contentsOf: required[0]) == Data("diskwing-gui-samples-v1\n".utf8), FileManager.default.isExecutableFile(atPath: required[3].path) else { throw sampleFailure() }
        let home = URL(fileURLWithPath: required[1].path, isDirectory: true).standardizedFileURL
        let store = Store(base: required[2])
        _ = try store.read(AppSettings.self, name: "settings.json"); _ = try store.preferences()
        return AppContext(home: home, store: store, helper: required[3], container: root, samples: SampleState())
    }
    static func sampleFailure() -> Error { CacheSSDError.message(L10n.text("Não foi possível iniciar o modo de amostras. Escolha uma pasta existente, sem links e com espaço disponível.")) }
    func allows(_ url: URL) -> Bool {
        guard let container else { return true }
        guard url.isFileURL else { return false }
        // Check lexical containment before inspecting components. Only the
        // system's equivalent /var spelling is normalized; custom links fail.
        let prefixes = [container.path, container.standardizedFileURL.path]
        guard let prefix = prefixes.first(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) else { return false }
        let tail = String(url.path.dropFirst(prefix.count)).split(separator: "/").map(String.init)
        guard tail.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return false }
        var current = container
        for (offset, component) in tail.enumerated() {
            current.appendPathComponent(component)
            var value = stat()
            if lstat(current.path, &value) != 0 { return errno == ENOENT }
            if value.st_mode & S_IFMT == S_IFLNK { return false }
            if offset < tail.count - 1 && value.st_mode & S_IFMT != S_IFDIR { return false }
        }
        return true
    }
    func require(_ urls: [URL]) throws { guard urls.allSatisfy(allows) else { throw CacheSSDError.message(L10n.text("O modo de amostras só permite os arquivos gerados para este teste.")) } }
    func volumes() -> [VolumeInfo] {
        guard let root = container, let samples else { return Volumes.list() }
        return Self.sampleVolumes(root: root, home: home, connected: samples.availability.connected)
    }
    nonisolated private static func sampleVolumes(root: URL, home: URL, connected: Bool) -> [VolumeInfo] {
        let free = Volumes.free(at: root), total = free + 8_589_934_592
        var values = [VolumeInfo(uuid: "DISKWING-SAMPLE-INTERNAL", name: "Mac de amostra", path: home.path, totalBytes: total, freeBytes: free, isInternal: true, isWritable: true)]
        if connected { values.append(VolumeInfo(uuid: "DISKWING-SAMPLE-EXTERNAL", name: "SSD de amostra", path: root.appendingPathComponent("sample-ssd").path, totalBytes: total, freeBytes: free, isInternal: false, isWritable: true)) }
        return values
    }
    func volume(_ uuid: String) -> VolumeInfo? { volumes().first { $0.uuid == uuid } }
    func inspect(_ tool: CacheDescriptor) -> AdapterStatus {
        if isSamples { return AdapterStatus(toolID: tool.id, adapterVersion: CacheAdapters.version, version: CacheAdapters.qualifiedVersions[tool.id], effectiveCachePath: tool.source.path, state: "native-available", explanation: "Cache gerado para teste. Nenhuma ferramenta instalada será executada.", canReleaseSource: tool.canReleaseLocal) }
        return CacheAdapters.inspect(tool, home: home)
    }
    func migrationEngine() -> MigrationEngine {
        let provider: (String) -> VolumeInfo?
        if let root = container, let availability = samples?.availability {
            let home = home
            provider = { uuid in Self.sampleVolumes(root: root, home: home, connected: availability.connected).first { $0.uuid == uuid } }
        } else { provider = { Volumes.find(uuid: $0) } }
        return MigrationEngine(store: store, home: home, volumeProvider: provider, verifyNative: !isSamples)
    }
    func personalActions() -> PersonalActions {
        guard let root = container else { return PersonalActions(home: home, store: store) }
        return PersonalActions(home: home, store: store, trashHandler: { source in
            let path = root.appendingPathComponent("sample-trash/\(UUID().uuidString)/\(source.lastPathComponent)")
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: source, to: path); return path
        })
    }
    func recovery() -> RecoveryManager { RecoveryManager(store: store, home: home) }
    func reveal(_ urls: [URL]) throws { try require(urls); if let samples { samples.record("reveal"); return }; NSWorkspace.shared.activateFileViewerSelecting(urls) }
    func open(_ url: URL) throws { try require([url]); if let samples { samples.record("open"); return }; NSWorkspace.shared.open(url) }
    func openPrivacy() { if let samples { samples.record("privacy"); return }; NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
    func setLogin(_ enabled: Bool) throws -> Bool {
        if let samples { samples.loginEnabled = enabled; samples.record("login"); return enabled }
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        return SMAppService.mainApp.status == .enabled
    }
    func xcodeLocal() throws { if let samples { samples.record("xcode-local"); return }; try XcodeIntegration.useLocalDerivedData(store: store) }
    func eject(_ volume: VolumeInfo) throws { try require([URL(fileURLWithPath: volume.path)]); if let samples { samples.volumeConnected = false; samples.record("eject"); return }; try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: volume.path)) }
    func requestNotifications() async throws -> Bool { if let samples { samples.record("notification-permission"); return samples.notificationsAllowed }; return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    func postNotification(_ content: UNMutableNotificationContent) async throws { if let samples { samples.record("notification"); return }; try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "DiskWing-growth", content: content, trigger: nil)) }
}
