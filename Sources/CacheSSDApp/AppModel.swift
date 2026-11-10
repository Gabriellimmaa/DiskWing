import SwiftUI
import AppKit
import ServiceManagement
import CacheSSDCore

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Visão geral", explorer = "Explorar espaço", caches = "Caches e SSD", history = "Histórico", preferences = "Ajustes"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .overview: return "internaldrive"; case .explorer: return "folder.badge.gearshape"; case .caches: return "externaldrive"; case .history: return "clock.arrow.circlepath"; case .preferences: return "slider.horizontal.3" }
    }
}

enum ReviewAction: Identifiable {
    case migration(CacheDescriptor), trash(ScanItem), move(ScanItem, URL), integration, disableIntegration, restore(CacheDescriptor), eject(VolumeInfo), xcodeLocal
    var id: String {
        switch self { case .migration(let t): return "migration-" + t.id; case .trash(let i): return "trash-" + i.path; case .move(let i, _): return "move-" + i.path; case .integration: return "integration"; case .disableIntegration: return "disable"; case .restore(let t): return "restore-" + t.id; case .eject(let v): return "eject-" + v.uuid; case .xcodeLocal: return "xcodeLocal" }
    }
    var title: String {
        switch self { case .migration(let t): return "Migrar cache de \(t.name)"; case .trash: return "Enviar à Lixeira"; case .move: return "Mover com cópia conferida"; case .integration: return "Integrar com o terminal"; case .disableIntegration: return "Desativar integração"; case .restore(let t): return "Restaurar cache de \(t.name)"; case .eject: return "Preparar para ejetar"; case .xcodeLocal: return "Usar local padrão do Xcode" }
    }
}

struct ToolSize { var logical: Int64; var allocated: Int64 }

@MainActor final class AppModel: ObservableObject {
    @Published var section: AppSection = .overview
    @Published var volumes: [VolumeInfo] = []
    @Published var settings: AppSettings
    @Published var report: ScanReport?
    @Published var breadcrumbs: [ScanItem] = []
    @Published var selectedPath: String?
    @Published var search = ""
    @Published var showLargest = false
    @Published var isScanning = false
    @Published var scanProgress: ScanProgress?
    @Published var operationMessage: String?
    @Published var notice: String?
    @Published var errorMessage: String?
    @Published var review: ReviewAction?
    @Published var releaseLocal = true
    @Published var toolSizes: [String: ToolSize] = [:]
    @Published var inventoryRunning = false
    @Published var history: [OperationRecord] = []
    @Published var interrupted: [MigrationJournal] = []
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    let store = Store()
    let tools = CacheCatalog.all()
    private var cancellation: CancellationFlag?
    private var observers: [NSObjectProtocol] = []
    var busy: Bool { operationMessage != nil }
    var currentFolder: ScanItem? { breadcrumbs.last }
    var selectedVolume: VolumeInfo? { volumes.first { $0.uuid == settings.selectedVolumeUUID } }
    var internalVolume: VolumeInfo? { volumes.first { $0.isInternal } }
    var visibleItems: [ScanItem] {
        let items = showLargest ? (report?.largestFiles ?? []) : (currentFolder?.children ?? [])
        return items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { $0.logicalBytes > $1.logicalBytes }
    }
    var selectedItem: ScanItem? { visibleItems.first { $0.path == selectedPath } }
    var helperURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/CacheSSDHelper") }
    var candidates: Int64 { toolSizes.values.reduce(0) { $0 + $1.logical } }

    init() {
        settings = store.settings()
        volumes = Volumes.list(); history = store.history(); interrupted = store.interruptedMigrations()
        if settings.selectedVolumeUUID == nil { settings.selectedVolumeUUID = volumes.first { !$0.isInternal && $0.name == "PortableSSD" }?.uuid }
        do { try store.save(settings) } catch { errorMessage = error.localizedDescription }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification, NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshVolumes() } })
        }
    }
    func refreshVolumes() { volumes = Volumes.list() }
    func saveSettings() { do { try store.save(settings) } catch { errorMessage = error.localizedDescription } }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Analisar pasta"; panel.message = "A análise lê nomes e tamanhos. Nenhum arquivo será alterado."
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }
    func scan(_ url: URL) {
        guard !isScanning && !busy else { return }
        let token = CancellationFlag(); cancellation = token; isScanning = true; scanProgress = nil
        selectedPath = nil; search = ""; section = .explorer
        Task {
            do {
                let value = try await Task.detached(priority: .userInitiated) {
                    try DiskScanner().scan(url, cancellation: token) { update in Task { @MainActor in self.scanProgress = update } }
                }.value
                report = value; breadcrumbs = [value.root]; showLargest = false; isScanning = false; cancellation = nil
                try? store.saveReport(value)
                if value.reachedLimit { notice = "A análise atingiu o limite de 200 mil itens. Os totais são parciais; escolha uma subpasta para aprofundar." }
                else if value.isCancelled { notice = "Análise interrompida. Os resultados já lidos estão disponíveis e são parciais." }
            } catch { isScanning = false; cancellation = nil; errorMessage = error.localizedDescription }
        }
    }
    func cancel() { cancellation?.cancel() }
    func openFolder(_ item: ScanItem) {
        guard item.isDirectory else { NSWorkspace.shared.activateFileViewerSelecting([item.url]); return }
        breadcrumbs.append(item); selectedPath = nil; search = ""; showLargest = false
    }
    func goBack() { if breadcrumbs.count > 1 { breadcrumbs.removeLast(); selectedPath = nil } }
    func showInFinder(_ item: ScanItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    func reviewMove(_ item: ScanItem) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Escolher destino"; panel.message = "A cópia será conferida antes de enviar a origem à Lixeira."
        if panel.runModal() == .OK, let url = panel.url { review = .move(item, url) }
    }
    func refreshInventory() {
        guard !inventoryRunning && !busy else { return }
        inventoryRunning = true
        Task {
            for tool in tools {
                let size = await Task.detached(priority: .utility) { FileTree.measure(tool.source) }.value
                toolSizes[tool.id] = ToolSize(logical: size.logical, allocated: size.allocated)
            }
            inventoryRunning = false
        }
    }
    func setLocalOnly(allowDuringOperation: Bool = false) { guard !busy || allowDuringOperation else { return }; settings.useExternal = false; saveSettings(); notice = "Novas execuções usarão caches locais. Reabra ferramentas e terminais que ainda estejam usando o SSD." }
    func execute(_ action: ReviewAction) {
        guard !busy, !isScanning else { return }
        review = nil; operationMessage = "Preparando…"
        let remove = releaseLocal
        let helper = helperURL
        Task {
            do {
                switch action {
                case .migration(let tool):
                    let record = try await Task.detached(priority: .userInitiated) {
                        try MigrationEngine().migrate(toolID: tool.id, removeLocal: remove) { text in Task { @MainActor in self.operationMessage = text } }
                    }.value
                    notice = record.detail + ". Ative a integração com o terminal para direcionar novos comandos."
                case .restore(let tool):
                    try await Task.detached(priority: .userInitiated) { try MigrationEngine().restore(toolID: tool.id) { text in Task { @MainActor in self.operationMessage = text } } }.value
                    notice = "Cache restaurado no Mac. A cópia do SSD foi preservada."
                case .trash(let item):
                    let record = try await Task.detached { try PersonalActions().trash(item.url) }.value; notice = record.detail
                case .move(let item, let target):
                    let record = try await Task.detached { try PersonalActions().move(item.url, to: target) { text in Task { @MainActor in self.operationMessage = text } } }.value; notice = record.detail
                case .integration:
                    try ShellIntegration.install(helper: helper); notice = "Integração instalada. Abra um novo terminal para ativá-la. A configuração anterior tem uma cópia de segurança."
                case .disableIntegration:
                    try ShellIntegration.uninstall(); notice = "Integração removida. Abra um novo terminal para retornar aos padrões locais."
                case .xcodeLocal:
                    try XcodeIntegration.useLocalDerivedData(); notice = "O Xcode usará o local padrão no Mac. Os arquivos anteriores no SSD foram preservados."
                case .eject(let volume):
                    let previousMode = settings.useExternal
                    do {
                        settings.useExternal = false; try store.save(settings)
                        defer { settings.useExternal = previousMode; try? store.save(settings) }
                        let locations = settings.locations.values.filter { $0.volumeUUID == volume.uuid }.map { URL(fileURLWithPath: volume.path).appendingPathComponent($0.relativePath) }
                        let processes = try await Task.detached { try BusyInspector.inspect(paths: locations) }.value
                        guard processes.isEmpty else { throw CacheSSDError.message("Ejeção adiada. Encerre antes: " + processes.map { "\($0.name) (\($0.pid))" }.joined(separator: ", ")) }
                        try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: volume.path))
                        notice = "Ejeção solicitada ao macOS. Aguarde o volume desaparecer antes de desconectar. Ao reconectar, novas execuções poderão voltar ao SSD."
                    }
                }
                settings = store.settings(); history = store.history(); interrupted = store.interruptedMigrations(); refreshVolumes(); operationMessage = nil
                if case .migration = action { refreshInventory() }
            } catch { operationMessage = nil; settings = store.settings(); history = store.history(); interrupted = store.interruptedMigrations(); refreshVolumes(); errorMessage = error.localizedDescription }
        }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = SMAppService.mainApp.status == .enabled }
        catch { errorMessage = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    func exportReport() {
        guard let report else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "DiskWing-analise.json"; panel.allowedContentTypes = [.json]
        panel.message = "O relatório contém nomes e caminhos. Revise antes de compartilhá-lo."
        if panel.runModal() == .OK, let url = panel.url {
            do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; try encoder.encode(report).write(to: url, options: .atomic) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
