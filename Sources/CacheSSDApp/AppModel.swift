import SwiftUI
import AppKit
import ServiceManagement
import CacheSSDCore
import UserNotifications
import Combine
import Darwin

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Visão geral", explorer = "Explorar volumes", caches = "Caches no SSD", history = "Histórico", preferences = "Ajustes"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .overview: return "internaldrive"; case .explorer: return "folder.badge.gearshape"; case .caches: return "externaldrive"; case .history: return "clock.arrow.circlepath"; case .preferences: return "slider.horizontal.3" }
    }
}

enum ReviewAction: Identifiable {
    case graphicalRestore(String), graphicalResume(String), graphicalRecover(UUID), migration(CacheDescriptor), prepareCache(CacheDescriptor), cacheTransfer(CacheTransferPlan), trash(ScanItem), volumeTrash(ScanItem, VolumeTrashScope), move(ScanItem, URL), integration, disableIntegration, restore(CacheDescriptor), eject(VolumeInfo), xcodeLocal, recover(RecoveryAssessment), resolve(RecoveryAssessment)
    var id: String {
        switch self { case .graphicalRestore(let id): return "graphical-restore-" + id; case .graphicalResume(let id): return "graphical-resume-" + id; case .graphicalRecover(let id): return "graphical-recover-" + id.uuidString; case .cacheTransfer(let p): return "cache-transfer-" + p.id.uuidString; case .volumeTrash(_, let s): return "volume-trash-" + s.volumeUUID + s.relativePath; case .migration(let t): return "migration-" + t.id; case .prepareCache(let t): return "prepare-cache-" + t.id; case .trash(let i): return "trash-" + i.path; case .move(let i, _): return "move-" + i.path; case .integration: return "integration"; case .disableIntegration: return "disable"; case .restore(let t): return "restore-" + t.id; case .eject(let v): return "eject-" + v.uuid; case .xcodeLocal: return "xcodeLocal"; case .recover(let r): return "recover-" + r.id.uuidString; case .resolve(let r): return "resolve-" + r.id.uuidString }
    }
    var title: String {
        switch self { case .graphicalRestore: return L10n.text("Restaurar cache no Mac"); case .graphicalResume: return L10n.text("Retomar cache no SSD"); case .graphicalRecover: return L10n.text("Revisar recuperação do cache"); case .cacheTransfer: return L10n.text("Transferir e ativar"); case .volumeTrash, .trash: return L10n.text("Enviar à Lixeira"); case .migration(let t): return L10n.text("Migrar cache de \(t.name)"); case .prepareCache(let t): return L10n.text("Preparar novos caches de \(t.name)"); case .move: return L10n.text("Mover com cópia conferida"); case .integration: return L10n.text("Integrar com o terminal"); case .disableIntegration: return L10n.text("Desativar integração"); case .restore(let t): return L10n.text("Restaurar cache de \(t.name)"); case .eject: return L10n.text("Preparar para ejetar"); case .xcodeLocal: return L10n.text("Usar local padrão do Xcode"); case .recover(let value): return value.journal.kind == "restore" ? L10n.text("Concluir restauração") : L10n.text("Restaurar origem"); case .resolve: return L10n.text("Encerrar registro mantendo cópias") }
    }
}

private final class ScanProgressMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: ScanProgress?
    func send(_ value: ScanProgress) { lock.lock(); latest = value; lock.unlock() }
    func take() -> ScanProgress? { lock.lock(); defer { lock.unlock() }; let value = latest; latest = nil; return value }
}

private struct PendingVolumeScan: Sendable { let location: VolumeIndexLocation; let sessionID: UUID; let startedAt: Date }

struct ToolSize { var logical: Int64; var allocated: Int64; var complete = true; var missing = false }

@MainActor final class AppModel: ObservableObject {
    @Published var section: AppSection = .explorer
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
    @Published var volumeTargets: [VolumeScanTarget] = []
    @Published var explorerTarget: VolumeScanTarget?
    @Published var choosingVolume = true
    @Published var preferExternalIndex = true
    @Published private(set) var resumableVolumeIDs = Set<String>()
    private var pendingVolumeScans: [String: PendingVolumeScan] = [:]
    @Published var indexOnSSD = false
    @Published var explorerRevision = UUID()
    @Published var indexSuspended = false
    private var suspendedVolumeSessionID: UUID?
    @Published private(set) var analysisNeedsRefresh = false
    @Published var breadcrumbs: [ScanItem] = []
    @Published var selectedPath: String?
    @Published var search = "" { didSet { if oldValue != search { indexOffset = 0; reloadIndex() } } }
    @Published var showLargest = false { didSet { if oldValue != showLargest { indexOffset = 0; reloadIndex() } } }
    @Published var minimumMiB = "" { didSet { indexOffset = 0; reloadIndex() } }
    @Published var allocatedOrder = true { didSet { indexOffset = 0; reloadIndex() } }
    @Published var inspectedItem: ScanItem?
    @Published var treemapItems: [ScanItem] = []
    @Published var treemapOtherBytes: Int64 = 0
    @Published var treemapOtherCount = 0
    @Published var treeScrollRequest: (id: UUID, ordinal: Int)?
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
    @Published var review: ReviewAction? { didSet { releaseLocal = false } }
    @Published var releaseLocal = false
    @Published var toolSizes: [String: ToolSize] = [:]
    @Published var adapterStatuses: [String: AdapterStatus] = [:]
    @Published var inventoryRunning = false
    @Published var cacheEntries: [CacheTransferEntry] = []
    @Published var graphicalCacheCandidates: [GraphicalCacheCandidate] = []
    @Published var cacheSelectedIDs = Set<String>()
    @Published var cacheTransferResults: [CacheTransferItemResult] = []
    @Published var cacheAnalyzing = false
    @Published var cacheRegisteredIDs = Set<String>()
    @Published var cacheVerifiedAt: [String: Date] = [:]
    private var cacheNeedsReopen = Set<String>()
    @Published var cacheStateUnknown = false
    @Published var graphicalPendingTransfers: [GraphicalCacheJournal] = []
    @Published var history: [OperationRecord] = []
    @Published var interrupted: [MigrationJournal] = []
    @Published var recoveries: [RecoveryAssessment] = []
    @Published var loginEnabled = false
    @Published private(set) var activeAction: ReviewAction?
    let context: AppContext
    let store: Store
    let tools: [CacheDescriptor]
    let updates: Updates
    var home: URL { context.home }
    var isSamples: Bool { context.isSamples }
    var sampleState: SampleState? { context.samples }
    var isProductionBuild: Bool { !isSamples && Bundle.main.object(forInfoDictionaryKey: "DiskWingBuildProfile") as? String == "production" }
    var applicationVersionDescription: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (["DiskWing", version.flatMap { $0.isEmpty ? nil : $0 }, build.flatMap { $0.isEmpty ? nil : "(\($0))" }].compactMap { $0 }).joined(separator: " ")
    }
    var pendingRecoveryCount: Int {
        guard (try? context.requireStorage()) != nil else { return 1 }
        return Set(recoveries.map(\.id)).union(interrupted.map(\.id)).union(graphicalPendingTransfers.filter { $0.isPending }.map(\.id)).count + store.unreadableOperationRecords().count + store.pendingConfigurationRecords().count
    }
    var operationHint: String? {
        switch activeAction {
        case .graphicalRestore, .graphicalResume, .graphicalRecover, .cacheTransfer, .migration, .prepareCache, .restore, .eject: return L10n.text("Mantenha o SSD conectado")
        case .move: return L10n.text("Aguarde a conferência da cópia")
        default: return nil
        }
    }
    private var cancellation: CancellationFlag?
    private var scanningRoot: URL?
    private var observers: [NSObjectProtocol] = []
    private var updateObservation: AnyCancellable?
    private var volumeTargetRequest = UUID()
    private var volumeDiscoveryRunning = false, volumeDiscoveryRequested = false
    private var resumeDiscoveryCancellation = CancellationFlag()
    private var resumeReadTask: Task<[String: PendingVolumeScan], Never>?
    private var indexStorageVolumeUUID: String?
    var busy: Bool { operationMessage != nil || updates.sessionInProgress }
    var currentFolder: ScanItem? { breadcrumbs.last }
    var currentScopeAvailable: Bool {
        if indexSuspended { return false }
        if let target = explorerTarget {
            let identifier = context.volumeIdentityProvider()
            return target.roots.allSatisfy { root in
                guard context.scopeAvailable(root.url), identifier(root.url).caseInsensitiveCompare(root.volumeUUID) == .orderedSame,
                      let identity = try? FileIdentity(root.url) else { return false }
                return identity.device == root.identity.device && identity.inode == root.identity.inode
            }
        }
        return report.map { context.scopeAvailable($0.root.url) } ?? false
    }
    var selectedVolume: VolumeInfo? { volumes.first { $0.uuid == settings.selectedVolumeUUID } }
    var integrationIsCurrent: Bool { settings.shellIntegrationEnabled && ShellIntegration.isCurrent(store: store) }
    var destinationIssue: String? {
        guard let volume = selectedVolume else { return nil }
        do { let url = URL(fileURLWithPath: volume.path); try context.require([url]); try FileTree.validateDestination(url); return nil }
        catch { return error.localizedDescription }
    }
    var internalVolume: VolumeInfo? { volumes.first { $0.isInternal } }
    var visibleItems: [ScanItem] {
        if indexedSessionID != nil { return indexedItems }
        let items = showLargest ? (report?.largestFiles ?? []) : (currentFolder?.children ?? [])
        return items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { $0.logicalBytes > $1.logicalBytes }
    }
    var selectedItem: ScanItem? {
        if let inspectedItem, inspectedItem.path == selectedPath { return inspectedItem }
        return visibleItems.first { $0.path == selectedPath }
    }
    var helperURL: URL { context.helperURL }
    var candidates: Int64 { toolSizes.values.filter { $0.complete && !$0.missing }.reduce(0) { $0 + $1.logical } }
    var hasRegisteredCacheDestinations: Bool { !settings.locations.isEmpty || !cacheRegisteredIDs.isEmpty }
    var cacheWorkflowHeadline: String {
        if cacheStateUnknown { return L10n.text("Estado dos caches precisa de revisão") }
        if !hasRegisteredCacheDestinations { return L10n.text("Nenhum cache transferido") }
        if cacheTransferResults.contains(where: { $0.state == .transferring }) { return L10n.text("Transferindo") }
        let errors = cacheTransferResults.filter { $0.state == .error || $0.state == .exception }.count
        if errors > 0 { return L10n.text("\(errors) itens precisam de revisão") }
        let temporary = cacheTransferResults.filter { $0.state == .localTemporary }.count
        if temporary > 0 { return L10n.text("\(temporary) itens em modo temporário sem SSD") }
        let proven = cacheTransferResults.filter { $0.state == .ssdVerified }.count
        if proven > 0 { return L10n.text("Uso do SSD comprovado em \(proven) itens") }
        return L10n.text("Destinos preparados; uso ainda não comprovado")
    }
    var cacheWorkflowDetail: String {
        if !hasRegisteredCacheDestinations { return L10n.text("Escolha o SSD e analise os aplicativos para revisar a primeira transferência.") }
        if !canVerifyGraphicalCacheUsage { return L10n.text("Destinos de terminal preparados. Abra um novo terminal. Nesta versão, o DiskWing não verifica execuções já encerradas.") }
        return L10n.text("Reabra os aplicativos ou use um novo terminal. A verificação distingue configuração de gravação real no SSD.")
    }
    func cacheSizeKnown(_ entry: CacheTransferEntry) -> Bool {
        if entry.kind == .graphical { return graphicalCacheCandidates.first { $0.id == entry.id }?.measurementComplete ?? false }
        guard let size = toolSizes[entry.id] else { return false }; return size.complete || size.missing
    }
    func cacheDestination(_ entry: CacheTransferEntry) -> URL? {
        if let destination = entry.destinationURL { return destination }
        guard let location = settings.locations[entry.id], let volume = context.volume(location.volumeUUID) else { return nil }
        return URL(fileURLWithPath: volume.path).appendingPathComponent(location.relativePath)
    }
    func cacheStateText(_ state: CacheUsageState) -> String {
        switch state {
        case .none: return L10n.text("Nenhum cache transferido")
        case .transferring: return L10n.text("Transferindo")
        case .configuredNeedsReopen: return L10n.text("Configurado; aguardando reabertura ou uso")
        case .ssdVerified: return L10n.text("Uso do SSD comprovado")
        case .localTemporary: return L10n.text("Temporário sem SSD")
        case .exception: return L10n.text("Compatibilidade precisa de revisão")
        case .error: return L10n.text("Precisa de revisão")
        }
    }
    private func cacheResult(_ candidate: GraphicalCacheCandidate, status: GraphicalCacheStatus) -> CacheTransferItemResult {
        if status.state == .localTemporary { cacheNeedsReopen.insert(candidate.id) }
        cacheVerifiedAt[candidate.id] = status.verifiedAt
        let reopen = cacheNeedsReopen.contains(candidate.id) && status.state == .ssdVerified
        return CacheTransferItemResult(id: candidate.id, state: reopen ? .configuredNeedsReopen : status.state,
            detail: reopen ? "SSD reconectado. Reabra o aplicativo e verifique o uso novamente." : status.detail,
            recordID: status.recordID, sourceReleased: status.sourceReleased, sourceLogicalBytes: candidate.logicalBytes)
    }
    private func refreshRegisteredCacheStates() {
        guard !busy else { return }
        let graphical = context.graphicalEngine()
        for candidate in graphicalCacheCandidates where cacheRegisteredIDs.contains(candidate.id) {
            let result = cacheResult(candidate, status: graphical.status(candidate: candidate))
            cacheTransferResults.removeAll { $0.id == candidate.id }; cacheTransferResults.append(result)
        }
        for tool in tools {
            guard let location = settings.locations[tool.id] else { continue }
            let available = settings.useExternal && context.volume(location.volumeUUID) != nil
            let result = CacheTransferItemResult(id: tool.id, state: available ? .configuredNeedsReopen : .localTemporary,
                detail: available ? "Destino configurado. Use um novo terminal; uma configuração não comprova o uso do SSD." : "As próximas execuções usam o cache local temporário. Reabra ferramentas que ainda estejam em uso.", sourceLogicalBytes: toolSizes[tool.id]?.logical ?? 0)
            cacheTransferResults.removeAll { $0.id == tool.id }; cacheTransferResults.append(result)
        }
    }
    func invalidateCacheReview() { cacheSelectedIDs.removeAll(); cacheEntries = []; cacheTransferResults = [] }
    func analyzeCacheWorkflow() {
        guard !busy, !isScanning, !cacheAnalyzing else { return }
        do { try context.requireStorage() } catch { errorMessage = error.localizedDescription; return }
        cacheAnalyzing = true
        let context = context, tools = tools, cacheHome = home, sampleMode = isSamples
        Task {
            let graphics = await context.graphicalCandidates()
            let result = await Task.detached(priority: .userInitiated) {
                tools.map { tool in (tool, FileTree.measure(tool.source), sampleMode ? AppContext.sampleAdapterStatus(tool) : CacheAdapters.inspect(tool, home: cacheHome)) }
            }.value
            var entries: [CacheTransferEntry] = [], selected = Set<String>(), registered = Set(settings.locations.keys)
            for (tool, size, status) in result {
                adapterStatuses[tool.id] = status
                toolSizes[tool.id] = ToolSize(logical: size.logical, allocated: size.allocated, complete: size.isComplete, missing: size.missing)
                let empty = size.missing || size.isComplete && size.logical == 0
                let reason: String?
                if settings.locations[tool.id] != nil { reason = "Este item já possui um destino. Seu uso ainda precisa ser verificado." }
                else if status.state != "native-available" { reason = status.explanation }
                else if !size.missing && !size.isComplete { reason = "O tamanho deste cache não pôde ser confirmado. Ele será preservado." }
                else if !empty && (!tool.canReleaseLocal || !status.canReleaseSource) { reason = "A origem precisa permanecer no Mac nesta versão. Uma cópia não liberaria este espaço." }
                else { reason = nil; selected.insert(tool.id) }
                entries.append(CacheTransferEntry(id: tool.id, kind: .commandLine, title: tool.name, scopeLabel: tool.explanation, sourceURL: tool.source,
                                                  logicalBytes: size.logical, allocatedBytes: size.allocated, canReleaseSource: empty || status.canReleaseSource,
                                                  requiresReopen: true, isSourceMissing: empty, blockedReason: reason))
            }
            let graphical = context.graphicalEngine()
            var results: [CacheTransferItemResult] = tools.compactMap { tool in
                guard let location = settings.locations[tool.id] else { return nil }
                let available = context.volume(location.volumeUUID) != nil && settings.useExternal
                return CacheTransferItemResult(id: tool.id, state: available ? .configuredNeedsReopen : .localTemporary,
                    detail: available ? "Destino configurado. Use um novo terminal; uma configuração não comprova o uso do SSD." : "As próximas execuções usam o cache local temporário. Reabra ferramentas que ainda estejam em uso.",
                    sourceLogicalBytes: toolSizes[tool.id]?.logical ?? 0)
            }
            do { registered.formUnion(try graphical.registrations().map(\.candidateID)); cacheStateUnknown = false }
            catch { cacheStateUnknown = true; errorMessage = error.localizedDescription }
            for candidate in graphics {
                let status = graphical.status(candidate: candidate)
                let entry = candidate.transferEntry(destinationURL: status.destinationURL)
                entries.append(entry)
                if entry.blockedReason == nil && !registered.contains(entry.id) { selected.insert(entry.id) }
                if registered.contains(entry.id) || status.state == .error {
                    results.removeAll { $0.id == entry.id }
                    results.append(cacheResult(candidate, status: status))
                }
            }
            graphicalCacheCandidates = graphics; cacheRegisteredIDs = registered
            cacheEntries = entries; cacheSelectedIDs = selected; cacheTransferResults = results; cacheAnalyzing = false
        }
    }
    var selectedCacheTransferEntries: [CacheTransferEntry] {
        cacheEntries.filter { cacheSelectedIDs.contains($0.id) && $0.blockedReason == nil && !cacheRegisteredIDs.contains($0.id) }
    }
    var newCacheTransferBlocked: Bool { cacheStateUnknown || hasUnreadableRecoveryRecords || pendingRecoveryCount > 0 }
    func reviewCacheTransfer() {
        guard let volume = selectedVolume, !busy, !isScanning, !cacheAnalyzing else { return }
        guard !newCacheTransferBlocked else { errorMessage = L10n.text("Revise os registros de recuperação antes de transferir novos caches."); return }
        let entries = selectedCacheTransferEntries
        guard !entries.isEmpty else { return }
        review = .cacheTransfer(CacheTransferPlan(destinationVolume: volume, entries: entries))
    }
    func closeReviewedApplications(_ plan: CacheTransferPlan) {
        guard review?.id == ReviewAction.cacheTransfer(plan).id, !busy else { return }
        let selected = Set(plan.eligibleEntries.map(\.id))
        let applications = graphicalCacheCandidates.filter { selected.contains($0.id) }.compactMap(\.applicationURL)
        let refused = context.requestGracefulTermination(applications: applications)
        notice = refused.isEmpty ? L10n.text("Encerramento solicitado. Salve seu trabalho e conclua os diálogos dos aplicativos antes de transferir.") : L10n.text("Feche manualmente antes de continuar: \(refused.joined(separator: ", "))")
    }
    private func executeCacheTransfer(_ plan: CacheTransferPlan, cancellation: CancellationFlag) async throws {
        let engine = context.migrationEngine(), graphical = context.graphicalEngine(), cacheHome = home, cacheStore = store, helper = helperURL
        if plan.eligibleEntries.contains(where: { $0.kind == .commandLine }) && !integrationIsCurrent {
            try await Task.detached { try ShellIntegration.install(helper: helper, store: cacheStore, home: cacheHome) }.value
        }
        var failed = 0
        for entry in plan.eligibleEntries {
            if cancellation.isCancelled { break }
            operationMessage = L10n.text("Transferindo cache de \(entry.title)…")
            cacheTransferResults.removeAll { $0.id == entry.id }
            cacheTransferResults.append(CacheTransferItemResult(id: entry.id, state: .transferring, detail: "Copiando e conferindo antes de ativar o destino."))
            var result: CacheTransferItemResult
            do {
                try context.requireStorage(); try context.require([entry.sourceURL, URL(fileURLWithPath: plan.destinationVolume.path)])
                if entry.kind == .commandLine {
                    let record = try await Task.detached(priority: .userInitiated) {
                        entry.isSourceMissing ? try engine.prepareFutureCache(toolID: entry.id, cancellation: cancellation) : try engine.migrate(toolID: entry.id, removeLocal: true, cancellation: cancellation)
                    }.value
                    let released = !entry.isSourceMissing && record.detail == "Cópia conferida; origem liberada"
                    let detail = released || entry.isSourceMissing ? "Destino configurado. Use um novo terminal; uma configuração não comprova o uso do SSD." : "Destino configurado, mas a origem local foi mantida porque estava em uso. Este espaço não foi liberado."
                    result = CacheTransferItemResult(id: entry.id, state: .configuredNeedsReopen, detail: detail, recordID: record.id, sourceReleased: released, sourceLogicalBytes: entry.logicalBytes)
                } else {
                    guard let candidate = graphicalCacheCandidates.first(where: { $0.id == entry.id }) else { throw CacheSSDError.message(L10n.text("O aplicativo mudou desde a análise. Analise novamente.")) }
                    result = try await Task.detached(priority: .userInitiated) {
                        try graphical.transfer(candidate: candidate, volume: plan.destinationVolume, releaseSource: true, cancellation: cancellation) { progress in
                            Task { @MainActor in self.updateOperationProgress(progress.detail, token: cancellation) }
                        }
                    }.value
                }
                cacheRegisteredIDs.insert(entry.id); cacheSelectedIDs.remove(entry.id)
            } catch { failed += 1; result = CacheTransferItemResult(id: entry.id, state: .error, detail: error.localizedDescription) }
            cacheTransferResults.removeAll { $0.id == entry.id }; cacheTransferResults.append(result)
        }
        notice = failed > 0 ? L10n.text("Transferência parcial. Revise o resultado de cada aplicativo.") : cancellation.isCancelled ? L10n.text("Transferência interrompida. Os resultados concluídos e as cópias foram preservados.") : L10n.text("Destinos preparados. Reabra os aplicativos ou use um novo terminal para verificar o uso.")
    }
    var canVerifyGraphicalCacheUsage: Bool { graphicalCacheCandidates.contains { cacheRegisteredIDs.contains($0.id) } }
    func verifyCacheWorkflowUsage() {
        guard !busy, !isScanning, !cacheAnalyzing, canVerifyGraphicalCacheUsage else { return }
        let engine = context.graphicalEngine(), candidates = graphicalCacheCandidates, token = CancellationFlag()
        cacheAnalyzing = true; cancellation = token; operationMessage = L10n.text("Verificando uso e concluindo transferências…")
        Task {
            defer {
                operationMessage = nil; cancellation = nil; cacheAnalyzing = false
                reloadRecords(); refreshVolumes()
            }
            for candidate in candidates where cacheRegisteredIDs.contains(candidate.id) {
                if token.isCancelled { break }
                do {
                    let status = try await Task.detached(priority: .userInitiated) {
                        try engine.verifyUsage(candidate: candidate, cancellation: token) { progress in
                            Task { @MainActor in self.updateOperationProgress(progress.detail, token: token) }
                        }
                    }.value
                    cacheTransferResults.removeAll { $0.id == candidate.id }
                    if status.state == .ssdVerified { cacheNeedsReopen.remove(candidate.id) }
                    cacheTransferResults.append(cacheResult(candidate, status: status))
                } catch {
                    cacheTransferResults.removeAll { $0.id == candidate.id }
                    cacheTransferResults.append(CacheTransferItemResult(id: candidate.id, state: .error, detail: error.localizedDescription))
                }
            }
        }
    }

    init(context: AppContext) {
        self.context = context; store = context.store; tools = CacheCatalog.all(home: context.home)
        updates = Updates(store: context.store, disabled: context.isSamples)
        settings = AppSettings()
        do { try context.requireStorage() } catch { errorMessage = error.localizedDescription; return }
        settings = context.store.settings(); loginEnabled = context.loginEnabled
        volumes = context.volumes(); reloadRecords(); refreshVolumeTargets()
        do { preferences = try store.preferences() } catch { errorMessage = error.localizedDescription }
        L10n.preference = preferences.language
        updates.operationInProgress = { [weak self] in self?.operationMessage != nil || self?.isScanning == true }
        updateObservation = updates.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        context.samples?.onChange = { [weak self] change in
            guard let self else { return }
            self.objectWillChange.send()
            switch change { case .volumes: self.refreshVolumes(); case .power: self.powerStateDidChange(); case .preferences: break }
        }
        startMonitoring()
        guard !context.isSamples else { return }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification, NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshVolumes() } })
        }
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.powerStateDidChange() } })
    }
    func refreshVolumes() {
        do { try context.requireStorage() } catch { errorMessage = error.localizedDescription; return }
        volumes = context.volumes()
        if let scanningRoot, !context.scopeAvailable(scanningRoot) { cancellation?.cancel() }
        if let uuid = indexStorageVolumeUUID, !volumes.contains(where: { $0.uuid == uuid }) {
            cancellation?.cancel()
            if !isScanning, let closing = suspendExplorerIndex() {
                Task { do { try await Task.detached(priority: .utility) { try closing.close() }.value } catch { errorMessage = error.localizedDescription } }
            }
        }
        if explorerTarget != nil && !currentScopeAvailable {
            cancellation?.cancel(); analysisNeedsRefresh = report != nil
            selectedPath = nil; inspectedItem = nil; treemapItems = []; explorerRevision = UUID()
        }
        refreshGrowth(); startMonitoring(); refreshVolumeTargets(); refreshRegisteredCacheStates()
    }
    func refreshVolumeTargets() {
        if volumeDiscoveryRunning { volumeDiscoveryRequested = true; resumeDiscoveryCancellation.cancel(); return }
        volumeDiscoveryRunning = true
        let discoveryCancellation = CancellationFlag(); resumeDiscoveryCancellation = discoveryCancellation
        let sampleMode = isSamples, request = UUID(); volumeTargetRequest = request
        let context = context
        let internalDirectory = store.base, external = selectedVolume, installation = settings.installationID
        let identifier = context.volumeIdentityProvider()
        Task {
            defer {
                volumeDiscoveryRunning = false
                if volumeDiscoveryRequested { volumeDiscoveryRequested = false; refreshVolumeTargets() }
            }
            let supplied = await context.scanVolumes()
            guard volumeTargetRequest == request, !discoveryCancellation.isCancelled else { return }
            let values = await Task.detached(priority: .userInitiated) {
                sampleMode ? Volumes.scanTargets(volumes: supplied, metadata: { _ in nil }) : Volumes.scanTargets(volumes: supplied)
            }.value
            guard volumeTargetRequest == request, !discoveryCancellation.isCancelled else { return }; volumeTargets = values
            let reading = Task.detached(priority: .utility) {
                Self.findPendingVolumeScans(targets: values, internalDirectory: internalDirectory, external: external,
                    installationID: installation, identifier: identifier, sampleMode: sampleMode, cancellation: discoveryCancellation)
            }
            resumeReadTask = reading
            let pending = await reading.value; resumeReadTask = nil
            guard volumeTargetRequest == request, !discoveryCancellation.isCancelled else { return }
            pendingVolumeScans = pending; resumableVolumeIDs = Set(pending.keys)
        }
    }
    nonisolated private static func findPendingVolumeScans(targets: [VolumeScanTarget], internalDirectory: URL,
        external: VolumeInfo?, installationID: String, identifier: @escaping (URL) -> String, sampleMode: Bool, cancellation: CancellationFlag) -> [String: PendingVolumeScan] {
        var result: [String: PendingVolumeScan] = [:]
        for target in targets {
            if cancellation.isCancelled { break }
            let choices: [VolumeInfo?] = external.map { [$0, nil] } ?? [nil]
            for volume in choices {
                if cancellation.isCancelled { break }
                do {
                    let location = try IndexStoragePolicy.location(internalDirectory: internalDirectory, externalVolume: volume, installationID: installationID, targetID: target.id,
                        filesystemType: sampleMode ? { _ in "apfs" } : IndexStoragePolicy.filesystemType, volumeIdentifier: identifier)
                    var metadata = stat()
                    guard lstat(location.url.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG, metadata.st_flags & UInt32(SF_DATALESS) == 0 else { continue }
                    let database = try location.openIndex(createIfMissing: false, volumeIdentifier: identifier)
                    defer { try? database.close() }
                    guard let sessionID = try database.resumableVolumeSession(targetID: target.id), let session = try database.session(id: sessionID) else { continue }
                    if let previous = result[target.id], previous.startedAt >= session.startedAt { continue }
                    result[target.id] = PendingVolumeScan(location: location, sessionID: sessionID, startedAt: session.startedAt)
                } catch { continue } // Unknown/missing indexes remain untouched; a new scan is an explicit choice.
            }
        }
        return result
    }
    func chooseVolume() { guard !busy, !isScanning else { return }; refreshVolumeTargets(); section = .explorer; choosingVolume = true }
    func scanVolume(_ requestedTarget: VolumeScanTarget, resume: Bool = false) {
        let target: VolumeScanTarget
        do {
            guard requestedTarget.schemaVersion == 1 else { throw CacheSSDError.message(L10n.text("A seleção de volumes é inválida ou pertence a uma versão mais recente.")) }
            if resume, let current = volumeTargets.first(where: { $0.id == requestedTarget.id }) {
                guard Set(current.roots.map(\.id)) == Set(requestedTarget.roots.map(\.id)), requestedTarget.roots.allSatisfy({ previous in current.roots.contains { $0.id == previous.id && $0.volumeUUID == previous.volumeUUID && $0.role == previous.role && $0.identity.inode == previous.identity.inode } }) else {
                    throw CacheSSDError.message(L10n.text("A análise não corresponde aos volumes selecionados."))
                }
                target = try VolumeScanTarget(id: current.id, name: current.name, roots: current.roots, displayRoot: current.displayRoot, dataNamespace: requestedTarget.dataNamespace)
            } else {
                target = resume ? requestedTarget : try VolumeScanTarget(id: requestedTarget.id, name: requestedTarget.name, roots: requestedTarget.roots, displayRoot: requestedTarget.displayRoot)
            }
        } catch { errorMessage = error.localizedDescription; return }
        guard !busy, !isScanning else { return }
        do { try context.requireStorage(); try context.require(target.roots.map(\.url)) }
        catch { errorMessage = error.localizedDescription; return }
        let previousSession = resume && explorerTarget?.id == target.id ? (indexedSessionID ?? suspendedVolumeSessionID) : nil
        let discovered = resume && previousSession == nil ? pendingVolumeScans[target.id] : nil
        if resume && previousSession == nil && discovered == nil {
            errorMessage = L10n.text("Nenhuma análise pendente foi encontrada. Reconecte o SSD original ou inicie uma nova análise."); return
        }
        let external: VolumeInfo?
        if resume, previousSession != nil {
            if let originalIndexVolume = indexStorageVolumeUUID {
                guard let volume = context.volume(originalIndexVolume) else {
                    errorMessage = L10n.text("Reconecte o SSD que guarda esta análise antes de retomá-la. A fila foi preservada."); return
                }
                external = volume
            } else { external = nil }
        } else if discovered != nil { external = nil }
        else {
            if preferExternalIndex, let issue = destinationIssue { errorMessage = issue; return }
            external = preferExternalIndex ? selectedVolume : nil
        }
        let usingInternalWhileSSDAbsent = external == nil && settings.selectedVolumeUUID != nil

        let sourceIdentifier = context.volumeIdentityProvider()
        let location: VolumeIndexLocation
        do {
            location = try discovered?.location ?? IndexStoragePolicy.location(internalDirectory: store.base, externalVolume: external, installationID: settings.installationID, targetID: target.id,
                                                       filesystemType: isSamples ? { _ in "apfs" } : IndexStoragePolicy.filesystemType,
                                                       volumeIdentifier: sourceIdentifier)
            try context.require([location.url])
        } catch { errorMessage = error.localizedDescription; return }
        let previous = previousSession ?? discovered?.sessionID, scanHome = home, scanStore = store, excluded = [store.base], token = CancellationFlag()
        let progressMailbox = ScanProgressMailbox()
        cancellation = token; explorerTarget = target; choosingVolume = false; section = .explorer
        isScanning = true; scanProgress = nil; scanningRoot = target.displayRoot; indexOnSSD = location.storageVolumeUUID != nil; indexSuspended = false
        indexStorageVolumeUUID = location.storageVolumeUUID
        pageRequest = UUID(); indexedItems = []; indexOffset = 0; selectedPath = nil; inspectedItem = nil
        if !resume { report = nil; breadcrumbs = []; indexedSessionID = nil }
        search = ""; showLargest = false
        Task {
            while cancellation === token && isScanning {
                if let update = progressMailbox.take() { scanProgress = update }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        Task {
            do {
                let pair = try await Task.detached(priority: .userInitiated) {
                    let lease = try OperationLease(store: scanStore); defer { withExtendedLifetime(lease) {} }
                    let database = try location.openIndex(volumeIdentifier: sourceIdentifier)
                    let resumeID = resume ? previous : nil
                    let result = try VolumeScanner(home: scanHome, volumeIdentifier: sourceIdentifier, excludedRoots: excluded).scan(target, index: database, resumeSessionID: resumeID, policy: location.policy, cancellation: token) { update in
                        progressMailbox.send(update)
                    }
                    return (database, result, try database.volumeTarget(sessionID: result.id) ?? target)
                }.value
                explorerTarget = pair.2
                index = pair.0; report = pair.1; indexedSessionID = pair.1.id; suspendedVolumeSessionID = nil; indexSuspended = false
                breadcrumbs = [pair.1.root]; analysisNeedsRefresh = false; explorerRevision = UUID()
                isScanning = false; cancellation = nil; scanningRoot = nil; reloadIndex()
                if pair.1.isPartial { notice = L10n.text("Análise parcial. Você pode continuar após restabelecer acesso ou espaço.") }
                else if usingInternalWhileSSDAbsent { notice = L10n.text("SSD ausente. Esta nova análise usa o índice limitado no Mac; índices anteriores no SSD foram preservados.") }
            } catch { isScanning = false; cancellation = nil; scanningRoot = nil; indexSuspended = index == nil && report != nil; errorMessage = error.localizedDescription }
        }
    }
    @discardableResult private func suspendExplorerIndex() -> ScanIndex? {
        let closing = index
        if let session = indexedSessionID { suspendedVolumeSessionID = session }
        index = nil; indexedSessionID = nil; pageRequest = UUID(); explorerRevision = UUID(); indexLoading = false
        indexedItems = []; treemapItems = []; treemapOtherBytes = 0; treemapOtherCount = 0
        selectedPath = nil; inspectedItem = nil; indexSuspended = report != nil; analysisNeedsRefresh = report != nil
        return closing
    }
    func refreshExplorer() {
        if let target = explorerTarget { scanVolume(target) }
        else if let root = report?.root.url { scan(root) }
    }
    func resumeExplorer() { if let target = explorerTarget { scanVolume(target, resume: true) } }
    func saveSettings() {
        do {
            try context.requireStorage()
            let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
            var latest = store.settings()
            latest.selectedVolumeUUID = settings.selectedVolumeUUID; latest.useExternal = settings.useExternal
            try store.save(latest); settings = latest
        } catch { if (try? context.requireStorage()) != nil { settings = store.settings() }; errorMessage = error.localizedDescription }
    }
    func chooseFolder() {
        guard !busy, !isScanning else { return }
        if isSamples { scan(home.appendingPathComponent("Downloads")); return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("Analisar pasta"); panel.message = L10n.text("A análise lê nomes e tamanhos. Nenhum arquivo será alterado.")
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }
    func scanInternalStorage() {
        guard let root = context.internalDataRoot() else {
            errorMessage = L10n.text("O volume de dados interno não pôde ser identificado. Escolha uma pasta para analisar.")
            return
        }
        scan(root)
    }
    func scan(_ url: URL, focus: Bool = true) {
        guard !isScanning && !busy else { return }
        do { try context.requireStorage(); try context.require([url]) } catch { errorMessage = error.localizedDescription; return }
        guard context.scopeAvailable(url) else { errorMessage = L10n.text("A pasta ou o SSD está indisponível. Ausência não é espaço liberado."); return }
        explorerTarget = nil; choosingVolume = false; indexStorageVolumeUUID = nil; indexOnSSD = false
        let scanHome = home
        let volumeIdentifier = context.scanVolumeIdentifier()
        let token = CancellationFlag(); cancellation = token; scanningRoot = url; isScanning = true; scanProgress = nil
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
                    let value = try IndexedScanner(home: scanHome, volumeIdentifier: volumeIdentifier).scan(url, index: database, cancellation: token) { update in Task { @MainActor in self.scanProgress = update } }
                    return (database, value)
                }.value
                if focus || report?.root.path == pair.1.root.path {
                    index = pair.0; report = pair.1
                    analysisNeedsRefresh = false
                    let restored = focus ? [] : previousPaths.compactMap { try? pair.0.item(sessionID: pair.1.id, path: $0) }
                    breadcrumbs = restored.isEmpty ? [pair.1.root] : restored
                    indexedSessionID = pair.1.id
                    if focus { showLargest = false }
                    reloadIndex(); refreshGrowth()
                }
                notifyGrowthIfNeeded(database: pair.0, path: pair.1.root.path)
                isScanning = false; cancellation = nil; scanningRoot = nil
                if (try? context.requireStorage()) != nil { try? store.saveReport(pair.1) }
                if pair.1.reachedLimit { notice = L10n.text("Análise parcial: limite de itens, espaço ou acesso. Escolha uma subpasta para aprofundar.") }
                else if pair.1.isCancelled { notice = L10n.text("Análise interrompida. Os itens já lidos permanecem pesquisáveis e os totais são parciais.") }
            } catch { isScanning = false; cancellation = nil; scanningRoot = nil; errorMessage = error.localizedDescription }
            schedulePendingRescan()
        }
    }
    func reloadIndex() {
        guard let database = index, let session = indexedSessionID else { return }
        let request = UUID(); pageRequest = request; indexLoading = true; selectedPath = nil; inspectedItem = nil
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
                indexedItems = page.items; indexTotal = page.total; indexLoading = false; selectedPath = nil; inspectedItem = nil
                refreshTreemap()
            } catch { if pageRequest == request { indexLoading = false; errorMessage = error.localizedDescription } }
        }
    }
    func treePage(parent: String, offset: Int, limit: Int) async throws -> IndexedPage {
        guard let database = index, let session = indexedSessionID else { throw CacheSSDError.message(L10n.text("Aguarde a análise do volume.")) }
        let query = search, files = showLargest, allocated = allocatedOrder
        let parentPath = query.isEmpty && !files ? parent : nil
        return try await Task.detached(priority: .userInitiated) {
            try database.page(sessionID: session, parent: parentPath, search: query, filesOnly: files, allocatedOrder: allocated, offset: offset, limit: limit)
        }.value
    }
    func treemapContainsSelection(_ item: ScanItem) -> Bool {
        guard let selectedPath else { return false }
        return selectedPath == item.path || item.isDirectory && selectedPath.hasPrefix(item.path == "/" ? "/" : item.path + "/")
    }
    var selectedTreemapContainer: ScanItem? { treemapItems.first { treemapContainsSelection($0) } }
    var selectedInTreemapRemainder: Bool {
        guard treemapOtherCount > 0, selectedTreemapContainer == nil, let path = selectedPath, let folder = currentFolder?.path else { return false }
        return path.hasPrefix(folder == "/" ? "/" : folder + "/")
    }
    func volumeTitle(_ target: VolumeScanTarget) -> String {
        if !target.isSystemGroup, target.roots.count == 1, target.roots[0].role == .system, target.name.hasSuffix(" — Sistema") {
            return L10n.text("\(String(target.name.dropLast(" — Sistema".count))) — Sistema")
        }
        if target.roots.count == 1, target.roots[0].role == .data, target.name == "Dados do armazenamento interno" { return L10n.text("Dados do armazenamento interno") }
        return target.name
    }
    func explorerName(_ item: ScanItem) -> String {
        guard let target = explorerTarget, target.isSystemGroup,
              item.path == target.displayRoot.appendingPathComponent(target.dataNamespace).path else { return item.name }
        return L10n.text("Outros dados do volume")
    }
    func clearExplorerSelection() { if selectedPath != nil || inspectedItem != nil { selectedPath = nil; inspectedItem = nil } }
    func selectExplorerItem(_ item: ScanItem, ordinal: Int? = nil) {
        if selectedPath != item.path || inspectedItem?.fileIdentity != item.fileIdentity { selectedPath = item.path; inspectedItem = item }
        if let ordinal { treeScrollRequest = (UUID(), ordinal) }
    }
    func refreshTreemap() {
        guard search.isEmpty, !showLargest, let folder = currentFolder, let session = indexedSessionID, let database = index else {
            treemapItems = []; treemapOtherBytes = 0; treemapOtherCount = 0; return
        }
        let allocated = allocatedOrder, revision = explorerRevision
        Task {
            do {
                let summary = try await Task.detached(priority: .userInitiated) {
                    try database.childrenSummary(sessionID: session, parent: folder.path, allocatedOrder: allocated, offset: 0, limit: 200)
                }.value
                let page = summary.page
                guard currentFolder?.path == folder.path, indexedSessionID == session, explorerRevision == revision, allocatedOrder == allocated, search.isEmpty else { return }
                treemapItems = page.items
                treemapOtherBytes = allocated ? summary.omittedAllocatedBytes : summary.omittedLogicalBytes
                treemapOtherCount = summary.omittedCount
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func nextPage() { guard indexOffset + indexedItems.count < indexTotal else { return }; indexOffset += 120; reloadIndex() }
    func previousPage() { indexOffset = max(0, indexOffset - 120); reloadIndex() }
    private func updateOperationProgress(_ text: String, token: CancellationFlag) {
        guard cancellation === token else { return }; operationMessage = L10n.message(text)
    }
    func cancel() { cancellation?.cancel() }
    func openFolder(_ item: ScanItem) {
        do { try context.require([item.url]) } catch { errorMessage = error.localizedDescription; return }
        guard item.isDirectory else { showInFinder(item); return }
        breadcrumbs.append(item); selectedPath = nil; search = ""; showLargest = false; indexOffset = 0; reloadIndex()
    }
    func goBack() { if breadcrumbs.count > 1 { breadcrumbs.removeLast(); selectedPath = nil; indexOffset = 0; reloadIndex() } }
    func navigateToBreadcrumb(_ position: Int) { guard position >= 0, position < breadcrumbs.count else { return }; breadcrumbs = Array(breadcrumbs.prefix(position + 1)); selectedPath = nil; inspectedItem = nil; indexOffset = 0; search = ""; reloadIndex() }
    func showInFinder(_ item: ScanItem) {
        if explorerTarget != nil {
            do { reveal([try explorerSource(item).url]) } catch { errorMessage = error.localizedDescription }
        } else { reveal([item.url]) }
    }
    private func explorerSource(_ item: ScanItem) throws -> (url: URL, volume: VolumeInfo) {
        guard let database = index, let session = indexedSessionID,
              let location = try database.sourceLocation(sessionID: session, path: item.path) else {
            throw CacheSSDError.message(L10n.text("Esta área agrupa dados do volume. Abra-a e escolha um item específico."))
        }
        try context.require([location.url, location.root.url])
        guard let volume = context.operationVolumeProvider()(location.volumeUUID),
              (try FileIdentity(URL(fileURLWithPath: volume.path))).device == location.rootIdentity.device else {
            throw CacheSSDError.message(L10n.text("O volume ou o item mudou desde a revisão. Analise novamente antes de continuar."))
        }
        return (location.url, volume)
    }
    func reviewTrash(_ item: ScanItem) {
        guard !busy, !isScanning else { return }
        do {
            guard trashPolicyReason(item) == nil else { throw CacheSSDError.message(trashPolicyReason(item) ?? L10n.text("A seleção precisa de revisão.")) }
            if explorerTarget != nil {
                let source = try explorerSource(item)
                let scope = try VolumeTrashScope(item: source.url, volume: source.volume, expectedIdentity: item.fileIdentity)
                review = .volumeTrash(item, scope)
            } else { review = .trash(item) }
        } catch { errorMessage = error.localizedDescription }
    }
    func reveal(_ urls: [URL]) { do { try context.reveal(urls) } catch { errorMessage = error.localizedDescription } }
    func openRecords() { do { try context.open(store.base) } catch { errorMessage = error.localizedDescription } }
    func openPrivacy() { context.openPrivacy() }
    func setSampleVolumeConnected(_ connected: Bool) {
        do { try sampleState?.setVolumeConnected(connected) }
        catch { errorMessage = L10n.text("Não foi possível mudar o estado do SSD de amostra. As cópias foram preservadas.") }
    }
    func cachePolicyReason(_ item: ScanItem) -> String? {
        guard context.allows(item.url) else { return L10n.text("O modo de amostras só permite os arquivos gerados para este teste.") }
        guard !analysisNeedsRefresh else { return L10n.text("Atualize a análise antes de revisar outra alteração.") }
        return PersonalActionPolicy.reasonPreventing(context.actionURL(item.url), home: home)
    }
    func trashPolicyReason(_ item: ScanItem) -> String? {
        guard context.allows(item.url) else { return L10n.text("O modo de amostras só permite os arquivos gerados para este teste.") }
        guard !cacheStateUnknown, !context.graphicalEngine().hasUnsafeRecoveryRecords() else { return L10n.text("Os registros dos caches precisam de revisão antes de alterar arquivos.") }
        guard !analysisNeedsRefresh else { return L10n.text("Atualize a análise antes de revisar outra alteração.") }
        guard explorerTarget == nil || currentScopeAvailable else { return L10n.text("O volume analisado está indisponível. Reconecte-o e atualize a análise.") }
        if explorerTarget != nil {
            do {
                let source = try explorerSource(item)
                guard isSamples || VolumeTrashScope.qualifiedFinderTrash(source.volume) else { return L10n.text("A Lixeira deste sistema de arquivos ainda não foi qualificada. Use o Finder.") }
                return PersonalActionPolicy.reasonPreventingTrash(source.url, on: source.volume, home: home, storeBase: store.base, protectedRoots: context.protectedOperationRoots())
            } catch { return error.localizedDescription }
        }
        return PersonalActionPolicy.reasonPreventingTrash(context.actionURL(item.url), home: home, storeBase: store.base)
    }
    func trashWarning(_ item: ScanItem) -> String? {
        if explorerTarget != nil, let source = try? explorerSource(item) {
            return PersonalActionPolicy.trashWarning(source.url, on: source.volume, home: home).map { L10n.message($0) }
        }
        return PersonalActionPolicy.trashWarning(context.actionURL(item.url), home: home).map { L10n.message($0) }
    }
    private func refreshAnalysisAfterMutation(_ action: ReviewAction) {
        switch action {
        case .graphicalRestore, .graphicalResume, .graphicalRecover, .volumeTrash, .cacheTransfer, .trash, .move, .migration, .prepareCache, .restore, .recover:
            guard let root = report?.root.url else { return }
            analysisNeedsRefresh = true; selectedPath = nil; pageRequest = UUID(); indexLoading = false
            if let target = explorerTarget { scanVolume(target) }
            else if context.scopeAvailable(root) { scan(root, focus: false) }
        default: break
        }
    }
    func sizeText(_ item: ScanItem, allocated: Bool = false) -> String {
        let bytes = allocated ? item.allocatedBytes : item.logicalBytes
        switch item.coverage {
        case .complete: return ByteText.format(bytes)
        case .partial: return L10n.text("Parcial: \(ByteText.format(bytes))")
        case .unknown: return L10n.text("Desconhecido")
        }
    }
    func cacheStatus(_ tool: CacheDescriptor) -> String? {
        guard settings.locations[tool.id] != nil else { return nil }
        guard let adapter = adapterStatuses[tool.id] else { return L10n.text("Destino preparado; verificação pendente") }
        guard adapter.state == "native-available" else { return L10n.text("Direcionamento indisponível; configuração preservada") }
        guard integrationIsCurrent else { return L10n.text("Destino preparado; integração pendente") }
        guard settings.useExternal else { return L10n.text("Novas execuções usam o Mac") }
        let available = CacheRouter.decisions(settings: settings, volumes: volumes).first { $0.toolID == tool.id }?.mode == "ssd"
        return available ? L10n.text("Destino no SSD disponível") : L10n.text("Cache local: SSD indisponível")
    }
    func recoveryTitle(_ value: RecoveryAssessment) -> String {
        switch value.journal.kind {
        case "personalMove": return L10n.text("Movimentação de arquivo")
        case "trash", "volumeTrash": return L10n.text("Envio à Lixeira")
        case "migration": return L10n.text("Migração de cache")
        case "restore": return L10n.text("Restauração de cache")
        default: return L10n.text("Operação pendente de revisão")
        }
    }
    func reviewMove(_ item: ScanItem) {
        if let root = context.container { review = .move(item, root.appendingPathComponent("personal-destination")); return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = L10n.text("Escolher destino"); panel.message = L10n.text("A cópia será conferida antes de enviar a origem à Lixeira.")
        if panel.runModal() == .OK, let url = panel.url { review = .move(item, url) }
    }
    func refreshInventory() {
        guard !inventoryRunning && !busy else { return }
        do { try context.requireStorage() } catch { errorMessage = error.localizedDescription; return }
        inventoryRunning = true
        Task {
            for tool in tools {
                guard (try? context.requireStorage()) != nil else { inventoryRunning = false; return }
                guard context.allows(tool.source) else {
                    toolSizes[tool.id] = ToolSize(logical: 0, allocated: 0, complete: false, missing: false)
                    adapterStatuses[tool.id] = AdapterStatus(toolID: tool.id, adapterVersion: CacheAdapters.version, version: nil, effectiveCachePath: nil, state: "custom-configuration", explanation: "O modo de amostras só permite os arquivos gerados para este teste.", canReleaseSource: false)
                    continue
                }
                let size = await Task.detached(priority: .utility) { FileTree.measure(tool.source) }.value
                toolSizes[tool.id] = ToolSize(logical: size.logical, allocated: size.allocated, complete: size.isComplete, missing: size.missing)
                if isSamples { adapterStatuses[tool.id] = context.inspect(tool) }
                else { let home = home; adapterStatuses[tool.id] = await Task.detached(priority: .utility) { CacheAdapters.inspect(tool, home: home) }.value }
            }
            inventoryRunning = false
        }
    }
    func setLocalOnly(allowDuringOperation: Bool = false) { guard !busy || allowDuringOperation else { return }; settings.useExternal = false; saveSettings(); notice = L10n.text("Novos comandos usarão caches locais. Reabra os terminais. Para aplicativos gráficos, revise Restaurar no Mac na lista de caches.") }
    private func validateAction(_ action: ReviewAction) throws {
        try context.requireStorage()
        switch action {
        case .volumeTrash, .trash, .move:
            guard !cacheStateUnknown, !context.graphicalEngine().hasUnsafeRecoveryRecords() else { throw CacheSSDError.message(L10n.text("Os registros dos caches precisam de revisão antes de alterar arquivos.")) }
        default: break
        }
        switch action {
        case .cacheTransfer(let plan):
            guard !newCacheTransferBlocked else { throw CacheSSDError.message(L10n.text("Revise os registros de recuperação antes de transferir novos caches.")) }
            guard selectedVolume?.uuid == plan.destinationVolume.uuid, selectedVolume?.path == plan.destinationVolume.path else { throw CacheSSDError.message(L10n.text("O SSD mudou desde a revisão. Analise novamente.")) }
            try context.require([URL(fileURLWithPath: plan.destinationVolume.path)] + plan.eligibleEntries.map(\.sourceURL))
        case .volumeTrash(_, let scope): try context.require([try scope.resolve(volumeProvider: context.operationVolumeProvider())])
        case .migration(let tool), .prepareCache(let tool), .restore(let tool):
            guard tools.contains(where: { $0.id == tool.id && $0.source == tool.source }) else { throw AppContext.sampleFailure() }
            try context.require([tool.source])
            if let volume = selectedVolume { try context.require([URL(fileURLWithPath: volume.path)]) }
        case .move(let item, let destination): try context.require([item.url, destination])
        case .trash(let item): try context.require([item.url])
        case .recover(let value), .resolve(let value):
            let paths = [value.journal.source, value.journal.destination, value.journal.staging, value.journal.quarantine, value.journal.trashPath].compactMap { $0 }.map { URL(fileURLWithPath: $0) }
            try context.require(paths)
        case .eject(let volume): try context.require([URL(fileURLWithPath: volume.path)])
        default: break
        }
    }
    func execute(_ action: ReviewAction) {
        guard !busy, !isScanning, review?.id == action.id else { return }
        do { try validateAction(action) } catch { review = nil; errorMessage = error.localizedDescription; return }
        let requestedRelease = releaseLocal
        review = nil; activeAction = action; operationMessage = L10n.text("Preparando…")
        let token = CancellationFlag(); cancellation = token
        let remove: Bool
        if case .migration(let tool) = action { remove = requestedRelease && tool.canReleaseLocal && adapterStatuses[tool.id]?.canReleaseSource == true }
        else { remove = false }
        let helper = helperURL, engine = context.migrationEngine(), personal = context.personalActions(), recovery = context.recovery()
        Task {
            do {
                try validateAction(action)
                switch action {
                case .graphicalRestore(let id), .graphicalResume(let id):
                    let graphical = context.graphicalEngine()
                    let shouldRestore: Bool
                    if case .graphicalRestore = action { shouldRestore = true } else { shouldRestore = false }
                    let result = try await Task.detached { shouldRestore ? try graphical.restore(candidateID: id, cancellation: token) : try graphical.resumeExternal(candidateID: id, cancellation: token) }.value
                    cacheTransferResults.removeAll { $0.id == id }; cacheTransferResults.append(result); notice = L10n.message(result.detail)
                case .graphicalRecover(let id):
                    let graphical = context.graphicalEngine()
                    let result = try await Task.detached { try graphical.recover(operationID: id, cancellation: token) }.value
                    cacheTransferResults.removeAll { $0.id == result.id }; cacheTransferResults.append(result); notice = L10n.message(result.detail)
                case .cacheTransfer(let plan):
                    try await executeCacheTransfer(plan, cancellation: token)
                case .volumeTrash(let item, let scope):
                    let scopedPersonal = context.personalActions(scope: scope)
                    try context.require([try scope.resolve(volumeProvider: context.operationVolumeProvider())])
                    let reviewedSource = URL(fileURLWithPath: scope.reviewedPath)
                    let record = try await Task.detached { try scopedPersonal.trash(reviewedSource, expectedIdentity: item.fileIdentity, scope: scope, cancellation: token) }.value
                    notice = record.detail
                case .migration(let tool):
                    let record = try await Task.detached(priority: .userInitiated) {
                        try engine.migrate(toolID: tool.id, removeLocal: remove, cancellation: token) { text in Task { @MainActor in self.updateOperationProgress(text, token: token) } }
                    }.value
                    notice = L10n.message(record.detail).trimmingCharacters(in: CharacterSet(charactersIn: ".")) + (integrationIsCurrent ? L10n.text(". Novas execuções em terminais com a integração atualizada podem usar o SSD.") : L10n.text(". Direcionamento pendente: ative a integração e abra um novo terminal."))
                case .prepareCache(let tool):
                    let record = try await Task.detached(priority: .userInitiated) {
                        try engine.prepareFutureCache(toolID: tool.id, cancellation: token) { text in Task { @MainActor in self.updateOperationProgress(text, token: token) } }
                    }.value
                    notice = L10n.message(record.detail).trimmingCharacters(in: CharacterSet(charactersIn: ".")) + (integrationIsCurrent ? L10n.text(". Novas execuções em terminais com a integração atualizada podem usar o SSD.") : L10n.text(". Direcionamento pendente: ative a integração e abra um novo terminal."))
                case .restore(let tool):
                    try await Task.detached(priority: .userInitiated) { try engine.restore(toolID: tool.id, cancellation: token) { text in Task { @MainActor in self.updateOperationProgress(text, token: token) } } }.value
                    notice = L10n.text("Cache restaurado no Mac. A cópia do SSD foi preservada.")
                case .trash(let item):
                    let source = context.actionURL(item.url)
                    try context.require([source])
                    let record = try await Task.detached { try personal.trash(source, expectedIdentity: item.fileIdentity, cancellation: token) }.value; notice = record.detail
                case .move(let item, let target):
                    let source = context.actionURL(item.url)
                    try context.require([source])
                    let record = try await Task.detached { try personal.move(source, to: target, expectedIdentity: item.fileIdentity, cancellation: token) { text in Task { @MainActor in self.updateOperationProgress(text, token: token) } } }.value; notice = record.detail
                case .recover(let assessment):
                    try await Task.detached { try recovery.restoreSource(id: assessment.id, cancellation: token) { text in Task { @MainActor in self.updateOperationProgress(text, token: token) } } }.value
                    notice = L10n.text("Origem recuperada. As demais cópias foram preservadas.")
                case .resolve(let assessment):
                    try recovery.keepCopiesAndResolve(id: assessment.id)
                    notice = L10n.text("Registro encerrado. Nenhuma cópia foi apagada.")
                case .integration:
                    try ShellIntegration.install(helper: helper, store: store, home: home); notice = L10n.text("Integração instalada. Abra um novo terminal para ativá-la. A configuração anterior tem uma cópia de segurança.")
                case .disableIntegration:
                    try ShellIntegration.uninstall(store: store, home: home); notice = L10n.text("Integração removida. Abra um novo terminal para retornar aos padrões locais.")
                case .xcodeLocal:
                    try context.xcodeLocal(); notice = L10n.text("O Xcode usará o local padrão no Mac. Os arquivos anteriores no SSD foram preservados.")
                case .eject(let volume):
                    resumeDiscoveryCancellation.cancel(); volumeTargetRequest = UUID()
                    if let reader = resumeReadTask { _ = await reader.value }
                    if indexStorageVolumeUUID == volume.uuid, let closing = suspendExplorerIndex() {
                        try await Task.detached(priority: .utility) { try closing.close() }.value
                    }
                    guard !token.isCancelled else { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
                    if isSamples { try context.eject(volume); notice = L10n.text("SSD de amostra desconectado. Nenhum disco físico foi ejetado."); break }
                    let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
                    var routingSettings = store.settings()
                    let previousMode = routingSettings.useExternal
                    do {
                        routingSettings.useExternal = false; try store.save(routingSettings)
                        defer { routingSettings.useExternal = previousMode; try? store.save(routingSettings) }
                        let graphicalLocations = try context.graphicalEngine().registrations().filter { $0.volumeUUID == volume.uuid }.map { URL(fileURLWithPath: volume.path).appendingPathComponent($0.relativeDestination) }
                        let locations = routingSettings.locations.values.filter { $0.volumeUUID == volume.uuid }.map { URL(fileURLWithPath: volume.path).appendingPathComponent($0.relativePath) } + graphicalLocations
                        let processes = try await Task.detached { try BusyInspector.inspect(paths: locations) }.value
                        guard processes.isEmpty else { throw CacheSSDError.message(L10n.text("Ejeção adiada. Encerre antes: ") + processes.map { L10n.text("\($0.name) (\($0.pid))") }.joined(separator: L10n.text(", "))) }
                        guard !token.isCancelled else { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
                        try context.eject(volume)
                        notice = L10n.text("Ejeção solicitada ao macOS. Aguarde o volume desaparecer antes de desconectar. Ao reconectar, novas execuções poderão voltar ao SSD.")
                    }
                }
                reloadRecords(); refreshVolumes(); operationMessage = nil; activeAction = nil; cancellation = nil
                switch action { case .migration, .prepareCache, .restore, .trash, .volumeTrash, .move, .recover: refreshInventory(); default: break }
                refreshAnalysisAfterMutation(action)
            } catch { operationMessage = nil; activeAction = nil; cancellation = nil; reloadRecords(); refreshVolumes(); errorMessage = error.localizedDescription; refreshAnalysisAfterMutation(action) }
        }
    }
    func reloadRecords() {
        do { try context.requireStorage() } catch { errorMessage = error.localizedDescription; return }
        settings = store.settings(); history = store.history(); interrupted = store.interruptedMigrations(); recoveries = context.recovery().pending()
        do {
            let graphical = context.graphicalEngine()
            cacheRegisteredIDs = Set(settings.locations.keys).union(try graphical.registrations().map(\.candidateID))
            graphicalPendingTransfers = try graphical.pendingTransfers(); cacheStateUnknown = false
        }
        catch { cacheStateUnknown = true }
    }
    var hasUnreadableRecoveryRecords: Bool {
        guard (try? context.requireStorage()) != nil else { return true }
        return cacheStateUnknown || context.graphicalEngine().hasUnsafeRecoveryRecords() || !store.unreadableOperationRecords().isEmpty || !store.pendingConfigurationRecords().isEmpty
    }
    var isWatchingCurrentRoot: Bool { report.map { item in preferences.watchedFolders.contains { $0.path == item.root.path } } ?? false }
    func savePreferences() {
        do { try context.requireStorage(); try store.write(preferences, name: "preferences.json") } catch { errorMessage = error.localizedDescription }
    }
    func setLanguage(_ language: String) { L10n.preference = language; preferences.language = language; savePreferences() }
    func watchCurrentRoot(_ enabled: Bool) {
        guard explorerTarget == nil else { monitoringStatus = L10n.text("A análise de volumes é atualizada pelo controle Atualizar análise."); return }
        guard let root = report?.root.url else { return }
        do { try context.require([root]) } catch { errorMessage = error.localizedDescription; return }
        guard context.scopeAvailable(root) else { monitoringStatus = L10n.text("A pasta ou o SSD está indisponível. Ausência não é espaço liberado."); return }
        if enabled && !isWatchingCurrentRoot && preferences.watchedFolders.count >= 10 { notice = L10n.text("Acompanhe até dez pastas para limitar o uso de recursos."); return }
        preferences.watchedFolders.removeAll { $0.path == root.path }
        if enabled {
            let uuid = context.scanVolumeIdentifier()(root)
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
            guard context.allows(URL(fileURLWithPath: folder.path)) else { continue }
            let url = URL(fileURLWithPath: folder.path)
            guard FileManager.default.isReadableFile(atPath: folder.path),
                  context.scanVolumeIdentifier()(url) == folder.volumeUUID else {
                monitoringStatus = L10n.text("Uma pasta acompanhada está indisponível; isso não representa espaço liberado.")
                continue
            }
            if isSamples { continue }
            do {
                monitors[folder.path] = try DirectoryEventMonitor(root: url) { [weak self] full in
                    Task { @MainActor in self?.scheduleRescan(url, full: full) }
                }
            } catch { monitoringStatus = error.localizedDescription }
        }
        schedulePendingRescan()
    }
    func scheduleRescan(_ root: URL, full: Bool) {
        guard context.allows(root) else { return }
        monitoringStatus = full ? L10n.text("Mudanças ou perda de eventos: uma nova análise é necessária.") : L10n.text("Mudanças detectadas na pasta acompanhada.")
        pendingRoots.insert(root.path); schedulePendingRescan()
    }
    func powerStateDidChange() {
        rescanTask?.cancel(); rescanTask = nil
        if context.isLowPower { monitoringStatus = L10n.text("Acompanhamento pausado no modo de pouca energia."); return }
        schedulePendingRescan()
    }
    func schedulePendingRescan() {
        guard preferences.backgroundRescans, !context.isLowPower, rescanTask == nil, let path = pendingRoots.sorted().first else { return }
        let root = URL(fileURLWithPath: path)
        let delay = max(context.minimumRescanDelay, context.minimumRescanInterval - Date().timeIntervalSince(lastBackgroundScan))
        rescanTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            rescanTask = nil
            guard preferences.backgroundRescans else { return }
            guard let watched = preferences.watchedFolders.first(where: { $0.path == root.path }),
                  context.scanVolumeIdentifier()(root) == watched.volumeUUID else { pendingRoots.remove(path); schedulePendingRescan(); return }
            guard !isScanning && !busy && !context.isLowPower else { schedulePendingRescan(); return }
            pendingRoots.remove(path)
            lastBackgroundScan = Date(); scan(root, focus: false)
        }
    }
    func refreshGrowth() {
        guard let database = index, let path = report?.root.path else { return }
        guard context.scopeAvailable(URL(fileURLWithPath: path)) else { growthComparison = nil; monitoringStatus = L10n.text("A pasta ou o SSD está indisponível. Ausência não é espaço liberado."); return }
        let period = growthDays, requireAvailable = !isSamples
        Task {
            do {
                let value = try await Task.detached(priority: .utility) { try database.growth(root: path, days: period == 0 ? nil : period, requireAvailable: requireAvailable) }.value
                guard report?.root.path == path, context.scopeAvailable(URL(fileURLWithPath: path)) else { return }
                growthComparison = value
            } catch { monitoringStatus = error.localizedDescription }
        }
    }
    func setGrowthAlerts(_ enabled: Bool) {
        if !enabled { preferences.growthAlerts = false; savePreferences(); return }
        Task {
            do {
                let granted = try await context.requestNotifications()
                preferences.growthAlerts = granted; savePreferences()
                if !granted { notice = L10n.text("Alertas não foram autorizados. O acompanhamento continua disponível no aplicativo.") }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    private func notifyGrowthIfNeeded(database: ScanIndex, path: String) {
        guard preferences.growthAlerts,
              context.scopeAvailable(URL(fileURLWithPath: path)),
              preferences.watchedFolders.contains(where: { $0.path == path }),
              Date().timeIntervalSince(preferences.lastAlerts[path] ?? .distantPast) > 86400 else { return }
        let threshold = preferences.growthThresholdBytes, requireAvailable = !isSamples
        Task {
            guard let value = try? await Task.detached(priority: .utility, operation: { try database.growth(root: path, requireAvailable: requireAvailable) }).value,
                  let delta = value.logicalDelta, delta >= threshold else { return }
            guard preferences.growthAlerts, context.scopeAvailable(URL(fileURLWithPath: path)), preferences.watchedFolders.contains(where: { $0.path == path }), Date().timeIntervalSince(preferences.lastAlerts[path] ?? .distantPast) > 86400 else { return }
            let content = UNMutableNotificationContent()
            content.title = "DiskWing"
            content.body = L10n.text("O uso de espaço de uma pasta acompanhada cresceu. Abra o aplicativo para revisar.")
            do { try await context.postNotification(content); preferences.lastAlerts[path] = Date(); savePreferences() }
            catch { monitoringStatus = error.localizedDescription }
        }
    }
    func setLogin(_ enabled: Bool) {
        do { loginEnabled = try context.setLogin(enabled) }
        catch { errorMessage = error.localizedDescription; loginEnabled = context.loginEnabled }
    }
    func exportReport() {
        guard report != nil else { return }
        if let root = context.container { exportReport(to: root.appendingPathComponent("sample-export-\(UUID().uuidString).json")); return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "DiskWing-analise.json"; panel.allowedContentTypes = [.json]
        panel.message = L10n.text("O relatório contém nomes e caminhos. Revise antes de compartilhá-lo.")
        if panel.runModal() == .OK, let url = panel.url { exportReport(to: url) }
    }
    func exportReport(to url: URL) {
        guard let report, !busy, !isScanning else { return }
        do { try context.requireStorage(); try context.require([url]) } catch { errorMessage = error.localizedDescription; return }
        do {
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
