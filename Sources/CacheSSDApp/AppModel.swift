import SwiftUI
import AppKit
import ServiceManagement
import CacheSSDCore
import UserNotifications
import Combine

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Visão geral", explorer = "Explorar espaço", caches = "Caches e SSD", history = "Histórico", preferences = "Ajustes"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .overview: return "internaldrive"; case .explorer: return "folder.badge.gearshape"; case .caches: return "externaldrive"; case .history: return "clock.arrow.circlepath"; case .preferences: return "slider.horizontal.3" }
    }
}

enum ReviewAction: Identifiable {
    case migration(CacheDescriptor), trash(ScanItem), move(ScanItem, URL), integration, disableIntegration, restore(CacheDescriptor), eject(VolumeInfo), xcodeLocal, recover(RecoveryAssessment), resolve(RecoveryAssessment)
    var id: String {
        switch self { case .migration(let t): return "migration-" + t.id; case .trash(let i): return "trash-" + i.path; case .move(let i, _): return "move-" + i.path; case .integration: return "integration"; case .disableIntegration: return "disable"; case .restore(let t): return "restore-" + t.id; case .eject(let v): return "eject-" + v.uuid; case .xcodeLocal: return "xcodeLocal"; case .recover(let r): return "recover-" + r.id.uuidString; case .resolve(let r): return "resolve-" + r.id.uuidString }
    }
    var title: String {
        switch self { case .migration(let t): return L10n.text("Migrar cache de \(t.name)"); case .trash: return L10n.text("Enviar à Lixeira"); case .move: return L10n.text("Mover com cópia conferida"); case .integration: return L10n.text("Integrar com o terminal"); case .disableIntegration: return L10n.text("Desativar integração"); case .restore(let t): return L10n.text("Restaurar cache de \(t.name)"); case .eject: return L10n.text("Preparar para ejetar"); case .xcodeLocal: return L10n.text("Usar local padrão do Xcode"); case .recover: return L10n.text("Restaurar origem"); case .resolve: return L10n.text("Encerrar registro mantendo cópias") }
    }
}

struct ToolSize { var logical: Int64; var allocated: Int64; var complete = true; var missing = false }

@MainActor final class AppModel: ObservableObject {
    @Published var section: AppSection = .overview
    @Published var volumes: [VolumeInfo] = []
    @Published var settings: AppSettings
    @Published var preferences = UserPreferences()
    @Published var growthComparison: GrowthComparison?
    @Published var monitoringStatus = ""
    @Published var growthDays = 0 { didSet { refreshGrowth() } }
    private var monitors: [String: DirectoryEventMonitor] = [:]
    private var rescanTask: Task<Void, Never>?
    private var lastBackgroundScan = Date.distantPast
    private var pendingRoots = Set<String>()
    @Published var report: ScanReport?
    @Published var breadcrumbs: [ScanItem] = []
    @Published var selectedPath: String?
    @Published var search = "" { didSet { if oldValue != search { indexOffset = 0; reloadIndex() } } }
    @Published var showLargest = false { didSet { if oldValue != showLargest { indexOffset = 0; reloadIndex() } } }
    @Published var minimumMiB = "" { didSet { indexOffset = 0; reloadIndex() } }
    @Published var allocatedOrder = false { didSet { indexOffset = 0; reloadIndex() } }
    @Published var indexedItems: [ScanItem] = []
    @Published var indexTotal = 0
    @Published var indexOffset = 0
    @Published var indexLoading = false
    @Published var indexedSessionID: UUID?
    private var index: ScanIndex?
    private var pageRequest = UUID()
    @Published var isScanning = false
    @Published var scanProgress: ScanProgress?
    @Published var operationMessage: String?
    @Published var notice: String?
    @Published var errorMessage: String?
    @Published var review: ReviewAction?
    @Published var releaseLocal = false
    @Published var toolSizes: [String: ToolSize] = [:]
    @Published var adapterStatuses: [String: AdapterStatus] = [:]
    @Published var inventoryRunning = false
    @Published var history: [OperationRecord] = []
    @Published var interrupted: [MigrationJournal] = []
    @Published var recoveries: [RecoveryAssessment] = []
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    let store = Store()
    let tools = CacheCatalog.all()
    let updates = Updates()
    private var cancellation: CancellationFlag?
    private var observers: [NSObjectProtocol] = []
    private var updateObservation: AnyCancellable?
    var busy: Bool { operationMessage != nil || updates.sessionInProgress }
    var currentFolder: ScanItem? { breadcrumbs.last }
    var selectedVolume: VolumeInfo? { volumes.first { $0.uuid == settings.selectedVolumeUUID } }
    var internalVolume: VolumeInfo? { volumes.first { $0.isInternal } }
    var visibleItems: [ScanItem] {
        if indexedSessionID != nil { return indexedItems }
        let items = showLargest ? (report?.largestFiles ?? []) : (currentFolder?.children ?? [])
        return items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { $0.logicalBytes > $1.logicalBytes }
    }
    var selectedItem: ScanItem? { visibleItems.first { $0.path == selectedPath } }
    var helperURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/CacheSSDHelper") }
    var candidates: Int64 { toolSizes.values.filter { $0.complete && !$0.missing }.reduce(0) { $0 + $1.logical } }

    init() {
        settings = store.settings()
        volumes = Volumes.list(); history = store.history(); interrupted = store.interruptedMigrations(); recoveries = RecoveryManager(store: store).pending()
        do { preferences = try store.preferences() } catch { errorMessage = error.localizedDescription }
        L10n.preference = preferences.language
        updates.operationInProgress = { [weak self] in self?.operationMessage != nil || self?.isScanning == true }
        updateObservation = updates.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        startMonitoring()
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification, NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshVolumes() } })
        }
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.schedulePendingRescan() } })
    }
    func refreshVolumes() { volumes = Volumes.list(); refreshGrowth(); startMonitoring() }
    func saveSettings() {
        do {
            let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
            var latest = store.settings()
            latest.selectedVolumeUUID = settings.selectedVolumeUUID; latest.useExternal = settings.useExternal
            try store.save(latest); settings = latest
        } catch { settings = store.settings(); errorMessage = error.localizedDescription }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("Analisar pasta"); panel.message = L10n.text("A análise lê nomes e tamanhos. Nenhum arquivo será alterado.")
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }
    func scan(_ url: URL, focus: Bool = true) {
        guard !isScanning && !busy else { return }
        let token = CancellationFlag(); cancellation = token; isScanning = true; scanProgress = nil
        let previousPaths = breadcrumbs.map(\.path)
        if focus {
            pageRequest = UUID(); indexedSessionID = nil; indexOffset = 0; indexedItems = []; indexTotal = 0
            selectedPath = nil; search = ""; section = .explorer
        }
        let databaseURL = store.base.appendingPathComponent("index.sqlite")
        Task {
            do {
                let pair = try await Task.detached(priority: .userInitiated) {
                    let database = try ScanIndex(url: databaseURL)
                    let value = try IndexedScanner().scan(url, index: database, cancellation: token) { update in Task { @MainActor in self.scanProgress = update } }
                    return (database, value)
                }.value
                if focus || report?.root.path == pair.1.root.path {
                    index = pair.0; report = pair.1
                    let restored = focus ? [] : previousPaths.compactMap { try? pair.0.item(sessionID: pair.1.id, path: $0) }
                    breadcrumbs = restored.isEmpty ? [pair.1.root] : restored
                    indexedSessionID = pair.1.id
                    if focus { showLargest = false }
                    reloadIndex(); refreshGrowth()
                }
                notifyGrowthIfNeeded(database: pair.0, path: pair.1.root.path)
                isScanning = false; cancellation = nil
                try? store.saveReport(pair.1)
                if pair.1.reachedLimit { notice = L10n.text("Análise parcial: limite de itens, espaço ou acesso. Escolha uma subpasta para aprofundar.") }
                else if pair.1.isCancelled { notice = L10n.text("Análise interrompida. Os itens já lidos permanecem pesquisáveis e os totais são parciais.") }
            } catch { isScanning = false; cancellation = nil; errorMessage = error.localizedDescription }
            schedulePendingRescan()
        }
    }
    func reloadIndex() {
        guard let database = index, let session = indexedSessionID else { return }
        let request = UUID(); pageRequest = request; indexLoading = true
        let query = search, offset = indexOffset, onlyFiles = showLargest, allocated = allocatedOrder
        let parent = query.isEmpty && !onlyFiles ? currentFolder?.path : nil
        let requestedMinimum = Double(minimumMiB.replacingOccurrences(of: ",", with: ".")) ?? 0
        let minimum = requestedMinimum.isFinite && requestedMinimum > 0 ? Int64(min(requestedMinimum, Double(Int64.max / 1_048_576)) * 1_048_576) : 0
        Task {
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
                guard pageRequest == request else { return }
                let page = try await Task.detached(priority: .userInitiated) {
                    try database.page(sessionID: session, parent: parent, search: query, filesOnly: onlyFiles, minimumBytes: minimum, allocatedOrder: allocated, offset: offset)
                }.value
                guard pageRequest == request, indexedSessionID == session else { return }
                indexedItems = page.items; indexTotal = page.total; indexLoading = false; selectedPath = nil
            } catch { if pageRequest == request { indexLoading = false; errorMessage = error.localizedDescription } }
        }
    }
    func nextPage() { guard indexOffset + indexedItems.count < indexTotal else { return }; indexOffset += 120; reloadIndex() }
    func previousPage() { indexOffset = max(0, indexOffset - 120); reloadIndex() }
    func cancel() { cancellation?.cancel() }
    func openFolder(_ item: ScanItem) {
        guard item.isDirectory else { NSWorkspace.shared.activateFileViewerSelecting([item.url]); return }
        breadcrumbs.append(item); selectedPath = nil; search = ""; showLargest = false; indexOffset = 0; reloadIndex()
    }
    func goBack() { if breadcrumbs.count > 1 { breadcrumbs.removeLast(); selectedPath = nil; indexOffset = 0; reloadIndex() } }
    func showInFinder(_ item: ScanItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    func reviewMove(_ item: ScanItem) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = L10n.text("Escolher destino"); panel.message = L10n.text("A cópia será conferida antes de enviar a origem à Lixeira.")
        if panel.runModal() == .OK, let url = panel.url { review = .move(item, url) }
    }
    func refreshInventory() {
        guard !inventoryRunning && !busy else { return }
        inventoryRunning = true
        Task {
            for tool in tools {
                let size = await Task.detached(priority: .utility) { FileTree.measure(tool.source) }.value
                toolSizes[tool.id] = ToolSize(logical: size.logical, allocated: size.allocated, complete: size.isComplete, missing: size.missing)
                adapterStatuses[tool.id] = await Task.detached(priority: .utility) { CacheAdapters.inspect(tool) }.value
            }
            inventoryRunning = false
        }
    }
    func setLocalOnly(allowDuringOperation: Bool = false) { guard !busy || allowDuringOperation else { return }; settings.useExternal = false; saveSettings(); notice = L10n.text("Novas execuções usarão caches locais. Reabra ferramentas e terminais que ainda estejam usando o SSD.") }
    func execute(_ action: ReviewAction) {
        guard !busy, !isScanning else { return }
        review = nil; operationMessage = L10n.text("Preparando…")
        let token = CancellationFlag(); cancellation = token
        let remove: Bool
        if case .migration(let tool) = action { remove = releaseLocal && tool.canReleaseLocal && adapterStatuses[tool.id]?.canReleaseSource == true }
        else { remove = false }
        let helper = helperURL
        Task {
            do {
                switch action {
                case .migration(let tool):
                    let record = try await Task.detached(priority: .userInitiated) {
                        try MigrationEngine().migrate(toolID: tool.id, removeLocal: remove, cancellation: token) { text in Task { @MainActor in self.operationMessage = text } }
                    }.value
                    notice = record.detail + L10n.text(". Ative a integração com o terminal para direcionar novos comandos.")
                case .restore(let tool):
                    try await Task.detached(priority: .userInitiated) { try MigrationEngine().restore(toolID: tool.id, cancellation: token) { text in Task { @MainActor in self.operationMessage = text } } }.value
                    notice = L10n.text("Cache restaurado no Mac. A cópia do SSD foi preservada.")
                case .trash(let item):
                    let record = try await Task.detached { try PersonalActions().trash(item.url, expectedIdentity: item.fileIdentity, cancellation: token) }.value; notice = record.detail
                case .move(let item, let target):
                    let record = try await Task.detached { try PersonalActions().move(item.url, to: target, expectedIdentity: item.fileIdentity, cancellation: token) { text in Task { @MainActor in self.operationMessage = text } } }.value; notice = record.detail
                case .recover(let assessment):
                    try await Task.detached { try RecoveryManager().restoreSource(id: assessment.id, cancellation: token) { text in Task { @MainActor in self.operationMessage = text } } }.value
                    notice = L10n.text("Origem recuperada. As demais cópias foram preservadas.")
                case .resolve(let assessment):
                    try RecoveryManager().keepCopiesAndResolve(id: assessment.id)
                    notice = L10n.text("Registro encerrado. Nenhuma cópia foi apagada.")
                case .integration:
                    try ShellIntegration.install(helper: helper); notice = L10n.text("Integração instalada. Abra um novo terminal para ativá-la. A configuração anterior tem uma cópia de segurança.")
                case .disableIntegration:
                    try ShellIntegration.uninstall(); notice = L10n.text("Integração removida. Abra um novo terminal para retornar aos padrões locais.")
                case .xcodeLocal:
                    try XcodeIntegration.useLocalDerivedData(); notice = L10n.text("O Xcode usará o local padrão no Mac. Os arquivos anteriores no SSD foram preservados.")
                case .eject(let volume):
                    let previousMode = settings.useExternal
                    do {
                        settings.useExternal = false; try store.save(settings)
                        defer { settings.useExternal = previousMode; try? store.save(settings) }
                        let locations = settings.locations.values.filter { $0.volumeUUID == volume.uuid }.map { URL(fileURLWithPath: volume.path).appendingPathComponent($0.relativePath) }
                        let processes = try await Task.detached { try BusyInspector.inspect(paths: locations) }.value
                        guard processes.isEmpty else { throw CacheSSDError.message(L10n.text("Ejeção adiada. Encerre antes: ") + processes.map { L10n.text("\($0.name) (\($0.pid))") }.joined(separator: L10n.text(", "))) }
                        try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: volume.path))
                        notice = L10n.text("Ejeção solicitada ao macOS. Aguarde o volume desaparecer antes de desconectar. Ao reconectar, novas execuções poderão voltar ao SSD.")
                    }
                }
                settings = store.settings(); history = store.history(); interrupted = store.interruptedMigrations(); recoveries = RecoveryManager(store: store).pending(); refreshVolumes(); operationMessage = nil; cancellation = nil
                if case .migration = action { refreshInventory() }
            } catch { operationMessage = nil; cancellation = nil; settings = store.settings(); history = store.history(); interrupted = store.interruptedMigrations(); recoveries = RecoveryManager(store: store).pending(); refreshVolumes(); errorMessage = error.localizedDescription }
        }
    }
    var isWatchingCurrentRoot: Bool { report.map { item in preferences.watchedFolders.contains { $0.path == item.root.path } } ?? false }
    func savePreferences() {
        do { try store.write(preferences, name: "preferences.json") } catch { errorMessage = error.localizedDescription }
    }
    func setLanguage(_ language: String) { L10n.preference = language; preferences.language = language; savePreferences() }
    func watchCurrentRoot(_ enabled: Bool) {
        guard let root = report?.root.url else { return }
        if enabled && !isWatchingCurrentRoot && preferences.watchedFolders.count >= 10 { notice = L10n.text("Acompanhe até dez pastas para limitar o uso de recursos."); return }
        preferences.watchedFolders.removeAll { $0.path == root.path }
        if enabled {
            let uuid = (try? root.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) ?? ""
            preferences.watchedFolders.append(WatchedFolder(path: root.path, volumeUUID: uuid))
        }
        savePreferences(); startMonitoring()
    }
    func removeWatch(_ path: String) {
        preferences.watchedFolders.removeAll { $0.path == path }; savePreferences(); startMonitoring()
    }
    func startMonitoring() {
        monitors.removeAll(); rescanTask?.cancel(); rescanTask = nil
        pendingRoots = pendingRoots.intersection(preferences.watchedFolders.map(\.path))
        for folder in preferences.watchedFolders.prefix(10) {
            let url = URL(fileURLWithPath: folder.path)
            guard FileManager.default.isReadableFile(atPath: folder.path),
                  (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) == folder.volumeUUID else {
                monitoringStatus = L10n.text("Uma pasta acompanhada está indisponível; isso não representa espaço liberado.")
                continue
            }
            do {
                monitors[folder.path] = try DirectoryEventMonitor(root: url) { [weak self] full in
                    Task { @MainActor in self?.scheduleRescan(url, full: full) }
                }
            } catch { monitoringStatus = error.localizedDescription }
        }
        schedulePendingRescan()
    }
    func scheduleRescan(_ root: URL, full: Bool) {
        monitoringStatus = full ? L10n.text("Mudanças ou perda de eventos: uma nova análise é necessária.") : L10n.text("Mudanças detectadas na pasta acompanhada.")
        pendingRoots.insert(root.path); schedulePendingRescan()
    }
    func schedulePendingRescan() {
        guard preferences.backgroundRescans, !ProcessInfo.processInfo.isLowPowerModeEnabled, rescanTask == nil, let path = pendingRoots.sorted().first else { return }
        let root = URL(fileURLWithPath: path)
        let delay = max(30, 900 - Date().timeIntervalSince(lastBackgroundScan))
        rescanTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            rescanTask = nil
            guard preferences.backgroundRescans else { return }
            guard let watched = preferences.watchedFolders.first(where: { $0.path == root.path }),
                  (try? root.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) == watched.volumeUUID else { pendingRoots.remove(path); schedulePendingRescan(); return }
            guard !isScanning && !busy && !ProcessInfo.processInfo.isLowPowerModeEnabled else { schedulePendingRescan(); return }
            pendingRoots.remove(path)
            lastBackgroundScan = Date(); scan(root, focus: false)
        }
    }
    func refreshGrowth() {
        guard let database = index, let path = report?.root.path else { return }
        let period = growthDays
        Task {
            do {
                let value = try await Task.detached(priority: .utility) { try database.growth(root: path, days: period == 0 ? nil : period) }.value
                guard report?.root.path == path else { return }
                growthComparison = value
            } catch { monitoringStatus = error.localizedDescription }
        }
    }
    func setGrowthAlerts(_ enabled: Bool) {
        if !enabled { preferences.growthAlerts = false; savePreferences(); return }
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                preferences.growthAlerts = granted; savePreferences()
                if !granted { notice = L10n.text("Alertas não foram autorizados. O acompanhamento continua disponível no aplicativo.") }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    private func notifyGrowthIfNeeded(database: ScanIndex, path: String) {
        guard preferences.growthAlerts,
              preferences.watchedFolders.contains(where: { $0.path == path }),
              Date().timeIntervalSince(preferences.lastAlerts[path] ?? .distantPast) > 86400 else { return }
        let threshold = preferences.growthThresholdBytes
        Task {
            guard let value = try? await Task.detached(priority: .utility, operation: { try database.growth(root: path) }).value,
                  let delta = value.logicalDelta, delta >= threshold else { return }
            guard preferences.growthAlerts, preferences.watchedFolders.contains(where: { $0.path == path }), Date().timeIntervalSince(preferences.lastAlerts[path] ?? .distantPast) > 86400 else { return }
            let content = UNMutableNotificationContent()
            content.title = "DiskWing"
            content.body = L10n.text("O uso de espaço de uma pasta acompanhada cresceu. Abra o aplicativo para revisar.")
            let request = UNNotificationRequest(identifier: "DiskWing-growth", content: content, trigger: nil)
            do { try await UNUserNotificationCenter.current().add(request); preferences.lastAlerts[path] = Date(); savePreferences() }
            catch { monitoringStatus = error.localizedDescription }
        }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = SMAppService.mainApp.status == .enabled }
        catch { errorMessage = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    func exportReport() {
        guard let report else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "DiskWing-analise.json"; panel.allowedContentTypes = [.json]
        panel.message = L10n.text("O relatório contém nomes e caminhos. Revise antes de compartilhá-lo.")
        if panel.runModal() == .OK, let url = panel.url {
            let token = CancellationFlag(); cancellation = token; operationMessage = L10n.text("Exportando relatório…")
            let databaseURL = store.base.appendingPathComponent("index.sqlite"), session = indexedSessionID
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        if let session { try ScanIndex(url: databaseURL).export(sessionID: session, to: url, cancellation: token) }
                        else { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; try encoder.encode(report).write(to: url, options: .atomic) }
                    }.value
                } catch { errorMessage = error.localizedDescription }
                cancellation = nil; operationMessage = nil
            }
        }
    }
}
