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
    var changeVolume: ((Bool) throws -> Void)?
    let availability = SampleAvailability()
    @Published private(set) var volumeConnected: Bool
    @Published var lowPower = false { didSet { onChange?(.power) } }
    @Published var loginEnabled = false
    @Published var notificationsAllowed = true
    private(set) var events: [String] = []
    init(connected: Bool = true) { volumeConnected = connected; availability.connected = connected }
    func setVolumeConnected(_ connected: Bool) throws {
        guard connected != volumeConnected else { return }
        guard let changeVolume else { throw AppContext.sampleFailure() }
        try changeVolume(connected)
        volumeConnected = connected; availability.connected = connected; onChange?(.volumes)
    }
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
    private let containerIdentity: FileIdentity?
    let minimumRescanDelay: TimeInterval
    let minimumRescanInterval: TimeInterval
    var isSamples: Bool { samples != nil }
    var isLowPower: Bool { samples?.lowPower ?? ProcessInfo.processInfo.isLowPowerModeEnabled }
    var loginEnabled: Bool { samples?.loginEnabled ?? (SMAppService.mainApp.status == .enabled) }
    private init(home: URL, store: Store, helper: URL, container: URL?, samples: SampleState?, rescanDelay: TimeInterval = 30, rescanInterval: TimeInterval = 900) {
        self.home = home; self.store = store; helperURL = helper; self.container = container; self.samples = samples
        containerIdentity = container.flatMap { try? FileIdentity($0) }
        minimumRescanDelay = rescanDelay; minimumRescanInterval = rescanInterval
        if let container {
            samples?.changeVolume = { [weak self] connected in
                guard let self else { throw AppContext.sampleFailure() }
                try self.requireStorage()
                let fm = FileManager.default
                let online = container.appendingPathComponent("sample-ssd"), offline = container.appendingPathComponent("offline-sample-ssd")
                let source = connected ? offline : online, destination = connected ? online : offline
                var info = stat()
                guard lstat(source.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                      lstat(destination.path, &info) != 0, errno == ENOENT else { throw AppContext.sampleFailure() }
                try fm.moveItem(at: source, to: destination)
            }
        }
    }
    static func live() -> AppContext {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AppContext(home: home, store: Store(base: home.appendingPathComponent("Library/Application Support/CacheSSD")), helper: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/CacheSSDHelper"), container: nil, samples: nil)
    }
    static func forLaunch(arguments: [String], bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> AppContext {
        switch try AppLaunchRequest.parse(arguments: arguments, bundleIdentifier: bundleIdentifier) {
        case .live: return live()
        case .create(let workspace): return try makeSamples(workspace: workspace)
        case .resume(let session): return try resumeSamples(session: session)
        }
    }
    static func makeSamples(workspace: URL, rescanDelay: TimeInterval = 30, rescanInterval: TimeInterval = 900) throws -> AppContext {
        try preparedSamples(SampleWorkspace.prepare(workspace: workspace), rescanDelay: rescanDelay, rescanInterval: rescanInterval)
    }
    static func resumeSamples(session: URL, rescanDelay: TimeInterval = 30, rescanInterval: TimeInterval = 900) throws -> AppContext {
        try preparedSamples(SampleWorkspace.validate(session: session), rescanDelay: rescanDelay, rescanInterval: rescanInterval)
    }
    static func preparedSamples(_ prepared: PreparedSampleSession, rescanDelay: TimeInterval = 30, rescanInterval: TimeInterval = 900) throws -> AppContext {
        let current = try FileIdentity(prepared.root)
        guard current.device == prepared.identity.device, current.inode == prepared.identity.inode else { throw sampleFailure() }
        let context = AppContext(home: prepared.home, store: Store(base: prepared.support), helper: prepared.helper, container: prepared.root, samples: SampleState(connected: prepared.connected), rescanDelay: rescanDelay, rescanInterval: rescanInterval)
        try context.requireStorage()
        return context
    }
    static func sampleFailure() -> Error { CacheSSDError.message(L10n.text("Não foi possível iniciar o modo de amostras. Escolha uma pasta existente, sem links e com espaço disponível.")) }
    func allows(_ url: URL) -> Bool {
        guard let container else { return true }
        var rootInfo = stat()
        guard let containerIdentity, lstat(container.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR,
              Int64(rootInfo.st_dev) == containerIdentity.device, UInt64(rootInfo.st_ino) == containerIdentity.inode else { return false }
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
    func requireStorage() throws {
        guard let container else { return }
        let marker = container.appendingPathComponent(".diskwing-sample-session")
        let required = [home, store.base, helperURL, marker]
        try require(required)
        for (offset, url) in required.enumerated() {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == (offset < 2 ? S_IFDIR : S_IFREG) else { throw Self.sampleFailure() }
        }
        // Every convenience reader below this context must reject redirected or
        // placeholder records before accessing them, including after resumption.
        guard let records = FileManager.default.enumerator(at: store.base, includingPropertiesForKeys: nil) else { throw Self.sampleFailure() }
        var count = 0
        for case let record as URL in records {
            count += 1
            var info = stat()
            guard count <= 4096, allows(record), lstat(record.path, &info) == 0,
                  [S_IFREG, S_IFDIR].contains(info.st_mode & S_IFMT), info.st_flags & UInt32(SF_DATALESS) == 0 else { throw Self.sampleFailure() }
        }
        let fd = Darwin.open(marker.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Self.sampleFailure() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? file.close() }
        guard try file.read(upToCount: 65) == Data("diskwing-gui-samples-v1\n".utf8) else { throw Self.sampleFailure() }
    }
    func volumes() -> [VolumeInfo] {
        guard let root = container, let samples else { return Volumes.list() }
        return Self.sampleVolumes(root: root, home: home, connected: samples.availability.connected)
    }
    nonisolated private static func sampleVolumes(root: URL, home: URL, connected: Bool) -> [VolumeInfo] {
        let free = Volumes.free(at: root), total = free + 8_589_934_592
        var values = [VolumeInfo(uuid: "DISKWING-SAMPLE-INTERNAL", name: "Mac de amostra", path: home.path, totalBytes: total, freeBytes: free, isInternal: true, isWritable: true)]
        let external = root.appendingPathComponent("sample-ssd")
        var info = stat()
        if connected && lstat(external.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR { values.append(VolumeInfo(uuid: "DISKWING-SAMPLE-EXTERNAL", name: "SSD de amostra", path: external.path, totalBytes: total, freeBytes: free, isInternal: false, isWritable: true)) }
        return values
    }
    func volume(_ uuid: String) -> VolumeInfo? { volumes().first { $0.uuid == uuid } }
    func scanVolumeIdentifier() -> (URL) -> String {
        if let container, let availability = samples?.availability {
            let external = container.appendingPathComponent("sample-ssd")
            let prefixes = [external.path, external.standardizedFileURL.path]
            return { url in
                if prefixes.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) { return availability.connected ? "DISKWING-SAMPLE-EXTERNAL-FILESYSTEM" : "" }
                return "DISKWING-SAMPLE-FILESYSTEM"
            }
        }
        return { (try? $0.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) ?? "" }
    }
    func scopeAvailable(_ url: URL) -> Bool {
        // Permission/coverage errors belong to the scanner's partial result;
        // an unavailable simulated device or absent root is a different state.
        allows(url) && (!isSamples || !scanVolumeIdentifier()(url).isEmpty) && FileManager.default.fileExists(atPath: url.path)
    }
    func inspect(_ tool: CacheDescriptor) -> AdapterStatus {
        if isSamples { return AdapterStatus(toolID: tool.id, adapterVersion: CacheAdapters.version, version: CacheAdapters.qualifiedVersions[tool.id], effectiveCachePath: tool.source.path, state: "native-available", explanation: "Cache gerado para teste. Nenhuma ferramenta instalada será executada.", canReleaseSource: tool.canReleaseLocal) }
        return CacheAdapters.inspect(tool, home: home)
    }
    private var operationBusyCheck: BusyCheck {
        if isSamples { return { _, _ in [] } }
        return { try BusyInspector.inspect(paths: $0, tool: $1) }
    }
    func migrationEngine() -> MigrationEngine {
        let provider: (String) -> VolumeInfo?
        if let root = container, let availability = samples?.availability {
            let home = home
            provider = { uuid in Self.sampleVolumes(root: root, home: home, connected: availability.connected).first { $0.uuid == uuid } }
        } else { provider = { Volumes.find(uuid: $0) } }
        return MigrationEngine(store: store, home: home, volumeProvider: provider, verifyNative: !isSamples, busyCheck: operationBusyCheck)
    }
    func personalActions() -> PersonalActions {
        guard let root = container else { return PersonalActions(home: home, store: store) }
        let identity = containerIdentity
        return PersonalActions(home: home, store: store, trashHandler: { source in
            let path = root.appendingPathComponent("sample-trash/\(UUID().uuidString)/\(source.lastPathComponent)")
            func validate() throws {
                var info = stat()
                guard let identity, lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                      Int64(info.st_dev) == identity.device, UInt64(info.st_ino) == identity.inode,
                      Paths.contains(source, in: root), Paths.physicalURL(source).standardizedFileURL == source.standardizedFileURL else {
                    throw CacheSSDError.message(L10n.text("O modo de amostras só permite os arquivos gerados para este teste."))
                }
                var ancestor = root
                let components = path.pathComponents.dropFirst(root.pathComponents.count)
                for component in components {
                    ancestor.appendPathComponent(component)
                    if lstat(ancestor.path, &info) != 0 {
                        if errno == ENOENT { break }
                        throw CacheSSDError.message(L10n.text("O modo de amostras só permite os arquivos gerados para este teste."))
                    }
                    guard info.st_mode & S_IFMT == S_IFDIR else { throw CacheSSDError.message(L10n.text("O modo de amostras só permite os arquivos gerados para este teste.")) }
                }
            }
            try validate()
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try validate()
            try FileManager.default.moveItem(at: source, to: path); return path
        }, busyCheck: operationBusyCheck)
    }
    func recovery() -> RecoveryManager { RecoveryManager(store: store, home: home, permittedRoot: container, busyCheck: operationBusyCheck) }
    func reveal(_ urls: [URL]) throws { try require(urls); if let samples { samples.record("reveal"); return }; NSWorkspace.shared.activateFileViewerSelecting(urls) }
    func open(_ url: URL) throws { try require([url]); if let samples { samples.record("open"); return }; NSWorkspace.shared.open(url) }
    func openPrivacy() { if let samples { samples.record("privacy"); return }; NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
    func setLogin(_ enabled: Bool) throws -> Bool {
        if let samples { samples.loginEnabled = enabled; samples.record("login"); return enabled }
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        return SMAppService.mainApp.status == .enabled
    }
    func xcodeLocal() throws { if let samples { samples.record("xcode-local"); return }; try XcodeIntegration.useLocalDerivedData(store: store) }
    func eject(_ volume: VolumeInfo) throws { try require([URL(fileURLWithPath: volume.path)]); if let samples { try samples.setVolumeConnected(false); samples.record("eject"); return }; try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: volume.path)) }
    func requestNotifications() async throws -> Bool { if let samples { samples.record("notification-permission"); return samples.notificationsAllowed }; return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    func postNotification(_ content: UNMutableNotificationContent) async throws { if let samples { samples.record("notification"); return }; try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "DiskWing-growth", content: content, trigger: nil)) }
}
