import Foundation
import Darwin
import CryptoKit

/// All mutating entry points use the same cross-process lease, including the CLI.
public final class OperationLease {
    private let descriptor: Int32
    public init(store: Store) throws {
        try FileManager.default.createDirectory(at: store.base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        descriptor = open(store.base.appendingPathComponent("migration.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CacheSSDError.message(L10n.text("Não foi possível preparar o registro local. Nenhuma alteração foi iniciada.")) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw CacheSSDError.message(L10n.text("Outra operação está em andamento. Aguarde sua conclusão."))
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

public enum OperationPhase: String, Codable, Sendable {
    case preparing, verifying, copying, copyVerified, publishing, published
    case releasing, trashing, completed, interrupted, cancelled, resolved
}

public struct FileIdentity: Codable, Equatable, Sendable {
    public let device: Int64
    public let inode: UInt64
    public var size: Int64?
    public var modifiedNanoseconds: Int64?
    public init(device: Int64, inode: UInt64, size: Int64? = nil, modifiedNanoseconds: Int64? = nil) {
        self.device = device; self.inode = inode; self.size = size; self.modifiedNanoseconds = modifiedNanoseconds
    }
    public init(_ url: URL) throws {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0 else { throw CacheSSDError.message(L10n.text("O item não está mais disponível.")) }
        guard metadata.st_mode & S_IFMT != S_IFLNK else { throw CacheSSDError.message(L10n.text("O item foi substituído por um link e foi preservado.")) }
        device = Int64(metadata.st_dev); inode = UInt64(metadata.st_ino)
        size = Int64(metadata.st_size); modifiedNanoseconds = Int64(metadata.st_mtimespec.tv_sec) &* 1_000_000_000 &+ Int64(metadata.st_mtimespec.tv_nsec)
    }
}

public struct OperationJournal: Codable, Identifiable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let kind: String
    public let toolID: String?
    public let sourceVolumeUUID: String?
    public let source: String
    public var destination: String?
    public var staging: String?
    public var quarantine: String?
    public var trashPath: String?
    public var sourceDigest: String?
    public var destinationDigest: String?
    public let sourceIdentity: FileIdentity
    public var phase: OperationPhase
    public var detail: String
    public let startedAt: Date
    public var updatedAt: Date
    public var isPending: Bool { phase != .completed && phase != .resolved }
    public init(kind: String, source: URL, destination: URL? = nil, toolID: String? = nil, id: UUID = UUID(), sourceVolumeUUID: String? = nil) throws {
        schemaVersion = 1; self.id = id; self.kind = kind; self.toolID = toolID
        self.sourceVolumeUUID = sourceVolumeUUID
        self.source = source.path; self.destination = destination?.path
        sourceIdentity = try FileIdentity(source)
        phase = .preparing; detail = "Origem preservada"
        startedAt = Date(); updatedAt = startedAt
    }
}

public final class OperationContext {
    public let store: Store
    public var journal: OperationJournal
    private let checkpoint: (OperationJournal) throws -> Void
    public init(store: Store, kind: String, source: URL, destination: URL? = nil, toolID: String? = nil, id: UUID = UUID(), sourceVolumeUUID: String? = nil, checkpoint: @escaping (OperationJournal) throws -> Void = { _ in }) throws {
        self.store = store; self.checkpoint = checkpoint
        journal = try OperationJournal(kind: kind, source: source, destination: destination, toolID: toolID, id: id, sourceVolumeUUID: sourceVolumeUUID)
        try advance(.preparing)
    }
    public func advance(_ phase: OperationPhase, detail: String? = nil) throws {
        journal.phase = phase; journal.updatedAt = Date()
        if let detail { journal.detail = detail }
        try store.writeDurably(journal, name: "operation-\(journal.id.uuidString).json")
        try checkpoint(journal)
    }
    public func assertSourceIdentity() throws {
        guard try FileIdentity(URL(fileURLWithPath: journal.source)) == journal.sourceIdentity else {
            throw CacheSSDError.message(L10n.text("A origem foi substituída durante a operação. Ela foi preservada."))
        }
    }
    public func recordFailure(_ error: Error, cancellation: CancellationFlag? = nil) {
        // A failure to save is surfaced by the caller; never remove data to make room for a log.
        journal.phase = cancellation?.isCancelled == true ? .cancelled : .interrupted
        journal.detail = error.localizedDescription; journal.updatedAt = Date()
        try? store.writeDurably(journal, name: "operation-\(journal.id.uuidString).json")
    }
}

public enum RecoveryAction: String, Sendable { case restoreSource, finishRestore }

public struct RecoveryAssessment: Identifiable, Sendable {
    public let journal: OperationJournal
    public var id: UUID { journal.id }
    public let canRestoreSource: Bool
    public let explanation: String
    public var recoveryAction: RecoveryAction? { canRestoreSource ? (journal.kind == "restore" ? .finishRestore : .restoreSource) : nil }
}

public final class RecoveryManager {
    private let store: Store
    private let home: URL
    private let checkpoint: (OperationJournal) throws -> Void
    private let supportedKinds: Set<String> = ["migration", "personalMove", "trash", "restore"]
    public init(store: Store = Store(), home: URL = FileManager.default.homeDirectoryForCurrentUser, checkpoint: @escaping (OperationJournal) throws -> Void = { _ in }) { self.store = store; self.home = home; self.checkpoint = checkpoint }

    public func pending() -> [RecoveryAssessment] {
        store.operations().filter(\.isPending).map { journal in
            guard journal.schemaVersion == 1 else { return RecoveryAssessment(journal: journal, canRestoreSource: false, explanation: "Registro de uma versão mais recente. Preserve as cópias e atualize o aplicativo.") }
            guard supportedKinds.contains(journal.kind) else { return RecoveryAssessment(journal: journal, canRestoreSource: false, explanation: "Tipo de operação desconhecido. Preserve o registro e as cópias para revisão.") }
            if journal.kind == "restore" {
                guard let (tool, target) = try? restoreTarget(journal) else { return RecoveryAssessment(journal: journal, canRestoreSource: false, explanation: "O destino da restauração não corresponde ao cache local. Preserve o registro para revisão.") }
                guard let settings = try? restoreSettings() else { return RecoveryAssessment(journal: journal, canRestoreSource: false, explanation: "Não foi possível ler a configuração da restauração. Os arquivos foram preservados.") }
                if let location = settings.locations[tool.id], !locationMatches(location, journal: journal, tool: tool, settings: settings) { return RecoveryAssessment(journal: journal, canRestoreSource: false, explanation: "A restauração encontrou conteúdo ou configuração diferente. As cópias foram preservadas para revisão.") }
                let available = exists(target) || exists(URL(fileURLWithPath: journal.source)) || journal.staging.map { exists(URL(fileURLWithPath: $0)) } == true
                return RecoveryAssessment(journal: journal, canRestoreSource: available, explanation: available ? "A restauração foi interrompida. Conclua a cópia local após conferência; conteúdo existente diferente será preservado." : "Conecte a cópia verificada para concluir a restauração do cache local.")
            }
            let source = URL(fileURLWithPath: journal.source)
            if FileManager.default.fileExists(atPath: source.path) {
                return RecoveryAssessment(journal: journal, canRestoreSource: false, explanation: "A origem continua disponível. Revise as cópias antes de encerrar este registro.")
            }
            let candidates = [journal.quarantine, journal.trashPath, journal.destination].compactMap { $0 }
            let available = candidates.contains { FileManager.default.fileExists(atPath: $0) }
            return RecoveryAssessment(journal: journal, canRestoreSource: available, explanation: available ? "Existe uma cópia de recuperação. Revise antes de restaurar a origem." : "A origem pode estar na Lixeira ou no SSD desconectado. Conecte o disco ou use a Lixeira do Finder; não remova cópias parciais.")
        }
    }

    /// Additive entry point; restore journals finish their local destination.
    public func recover(id: UUID, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (String) -> Void = { _ in }) throws {
        try restoreSource(id: id, cancellation: cancellation, progress: progress)
    }

    /// Legacy entry point retained. Restore journals dispatch to their local destination.
    public func restoreSource(id: UUID, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (String) -> Void = { _ in }) throws {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        guard var journal = store.operations().first(where: { $0.id == id }), journal.schemaVersion == 1, supportedKinds.contains(journal.kind) else { throw CacheSSDError.message(L10n.text("O registro de recuperação não está disponível.")) }
        if journal.kind == "restore" {
            if !journal.isPending { return }
            let (tool, _) = try restoreTarget(journal)
            let settings = try restoreSettings()
            if let location = settings.locations[tool.id], !locationMatches(location, journal: journal, tool: tool, settings: settings) { throw restoreConflict() }
            do { try finishRestore(&journal, cancellation: cancellation, progress: progress) }
            catch {
                journal.phase = cancellation.isCancelled ? .cancelled : .interrupted
                journal.detail = error.localizedDescription; journal.updatedAt = Date()
                try? store.writeDurably(journal, name: "operation-\(id.uuidString).json")
                throw error
            }
            return
        }
        guard journal.isPending else { throw CacheSSDError.message(L10n.text("O registro de recuperação não está disponível.")) }
        let source = URL(fileURLWithPath: journal.source)
        try validateSource(journal, source: source)
        guard !exists(source) else { throw CacheSSDError.message(L10n.text("A origem já existe e não será sobrescrita.")) }
        let quarantine = journal.quarantine.map { URL(fileURLWithPath: $0) }
        if let quarantine, FileManager.default.fileExists(atPath: quarantine.path) {
            guard quarantine.deletingLastPathComponent() == source.deletingLastPathComponent(),
                  quarantine.lastPathComponent == ".CacheSSD-\(journal.id.uuidString)" else { throw CacheSSDError.message(L10n.text("O caminho de recuperação não corresponde a esta operação.")) }
            guard let digest = journal.sourceDigest, try FileTree.digest(quarantine, tool: journal.toolID ?? "", cancellation: cancellation, workspace: store.base, progress: progress) == digest else {
                throw CacheSSDError.message(L10n.text("A origem em recuperação está incompleta. Preserve-a e revise a cópia no SSD."))
            }
            try FileTree.publishWithoutReplacing(quarantine, to: source)
        } else {
            let availableTrash = journal.trashPath.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            guard let path = availableTrash ?? journal.destination, let expected = availableTrash == nil ? journal.destinationDigest : journal.sourceDigest else {
                throw CacheSSDError.message(L10n.text("Conecte a cópia verificada ou recupere o item na Lixeira do Finder."))
            }
            let copy = URL(fileURLWithPath: path)
            guard copy.standardizedFileURL == copy.resolvingSymlinksInPath(),
                  try BusyInspector.inspect(paths: [copy]).isEmpty else { throw CacheSSDError.message(L10n.text("A cópia está indisponível, redirecionada ou em uso.")) }
            guard try FileTree.digest(copy, tool: journal.toolID ?? "", cancellation: cancellation, workspace: store.base, progress: progress) == expected else { throw CacheSSDError.message(L10n.text("A cópia mudou. Ela foi preservada para revisão manual.")) }
            let size = FileTree.measure(copy, cancellation: cancellation, progress: progress)
            guard size.isComplete, Volumes.free(at: source.deletingLastPathComponent()) > size.logical + 536_870_912 else { throw CacheSSDError.message(L10n.text("Não há espaço confirmado para restaurar a cópia.")) }
            let temp = source.deletingLastPathComponent().appendingPathComponent(".CacheSSD-recovery-\(journal.id.uuidString)")
            guard !FileManager.default.fileExists(atPath: temp.path) else { throw CacheSSDError.message(L10n.text("Há uma restauração parcial. Revise-a antes de tentar novamente.")) }
            journal.staging = temp.path
            try store.writeDurably(journal, name: "operation-\(id.uuidString).json")
            try FileTree.copyItem(copy, to: temp, tool: journal.toolID ?? "", cancellation: cancellation, progress: progress)
            guard try FileTree.digest(temp, tool: journal.toolID ?? "", cancellation: cancellation, workspace: store.base, progress: progress) == expected,
                  !exists(source) else { throw CacheSSDError.message(L10n.text("A restauração mudou ou a origem reapareceu. As cópias foram mantidas.")) }
            try FileTree.publishWithoutReplacing(temp, to: source)
        }
        journal.phase = .resolved; journal.updatedAt = Date(); journal.detail = "Origem restaurada; cópias de recuperação preservadas"
        try store.writeDurably(journal, name: "operation-\(id.uuidString).json")
        try store.append(OperationRecord(title: "Origem recuperada", detail: journal.detail, recoveryPath: source.path))
    }

    private func exists(_ url: URL) -> Bool { var info = stat(); return lstat(url.path, &info) == 0 }

    private func restoreTarget(_ journal: OperationJournal) throws -> (CacheDescriptor, URL) {
        guard let id = journal.toolID, let tool = CacheCatalog.find(id, home: home), let path = journal.destination else { throw restoreConflict() }
        let target = URL(fileURLWithPath: path)
        guard target.standardizedFileURL == tool.source.standardizedFileURL,
              target.standardizedFileURL == target.resolvingSymlinksInPath() else { throw restoreConflict() }
        return (tool, target)
    }
    private func restoreConflict() -> Error { CacheSSDError.message(L10n.text("A restauração encontrou conteúdo ou configuração diferente. As cópias foram preservadas para revisão.")) }

    private func restoreSettings() throws -> AppSettings {
        guard let value = try? store.read(AppSettings.self, name: "settings.json") else { throw CacheSSDError.message(L10n.text("Não foi possível ler a configuração da restauração. Os arquivos foram preservados.")) }
        return value
    }
    private func locationMatches(_ location: CacheLocation, journal: OperationJournal, tool: CacheDescriptor, settings: AppSettings) -> Bool {
        let relative = location.relativePath
        guard let recordedVolume = journal.sourceVolumeUUID,
              !recordedVolume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              recordedVolume.caseInsensitiveCompare(location.volumeUUID) == .orderedSame,
              location.toolID == tool.id, Paths.safeComponent(settings.installationID),
              relative.hasPrefix("MacCaches/CacheSSD/" + settings.installationID + "/" + tool.id + "/"),
              relative.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ Paths.safeComponent(String($0)) }) else { return false }
        let suffix = relative + (tool.destinationChild.isEmpty ? "" : "/" + tool.destinationChild)
        return URL(fileURLWithPath: journal.source).standardizedFileURL.path.hasSuffix("/" + suffix)
    }
    private func update(_ journal: inout OperationJournal, phase: OperationPhase) throws {
        journal.phase = phase; journal.updatedAt = Date()
        try store.writeDurably(journal, name: "operation-\(journal.id.uuidString).json")
        try checkpoint(journal)
    }

    /// A restore's source is the retained SSD copy; recovery completes destination.
    private func finishRestore(_ journal: inout OperationJournal, cancellation: CancellationFlag, progress: @escaping (String) -> Void) throws {
        let (tool, target) = try restoreTarget(journal), fm = FileManager.default
        let settings = try restoreSettings()
        if let location = settings.locations[tool.id], !locationMatches(location, journal: journal, tool: tool, settings: settings) { throw restoreConflict() }
        if let a = journal.sourceDigest, let b = journal.destinationDigest, a != b { throw restoreConflict() }
        let source = URL(fileURLWithPath: journal.source)
        var expected = journal.destinationDigest ?? journal.sourceDigest
        if expected == nil {
            // Legacy/preparing records have no digest yet; require the recorded source identity.
            guard settings.locations[tool.id] != nil, source.standardizedFileURL == source.resolvingSymlinksInPath(),
                  try FileIdentity(source) == journal.sourceIdentity else { throw restoreConflict() }
            expected = try FileTree.digest(source, tool: tool.id, cancellation: cancellation, workspace: store.base, progress: progress)
            guard try FileIdentity(source) == journal.sourceIdentity else { throw restoreConflict() }
            journal.sourceDigest = expected
            try update(&journal, phase: .verifying)
        }
        guard let expected else { throw restoreConflict() }
        if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }

        var targetInfo = stat()
        if lstat(target.path, &targetInfo) == 0 {
            guard targetInfo.st_mode & S_IFMT == S_IFDIR else { throw restoreConflict() }
            // Already published, including an empty cache: reconcile without replacing it.
            if try FileTree.digest(target, tool: tool.id, cancellation: cancellation, workspace: store.base, progress: progress) == expected {
                try finishRestoreConfiguration(&journal, tool: tool, target: target, expected: expected, cancellation: cancellation, progress: progress)
                return
            }
            guard (try fm.contentsOfDirectory(atPath: target.path)).isEmpty else { throw restoreConflict() }
        } else if errno != ENOENT { throw restoreConflict() }
        guard settings.locations[tool.id] != nil else { throw restoreConflict() }

        var stage: URL?
        if let path = journal.staging {
            let candidate = URL(fileURLWithPath: path), stem = ".CacheSSD-restore-recovery-\(journal.id.uuidString)-"
            let legacy = candidate.lastPathComponent == ".CacheSSD-restore-\(journal.id.uuidString)"
            let retry = candidate.lastPathComponent.hasPrefix(stem) && UUID(uuidString: String(candidate.lastPathComponent.dropFirst(stem.count))) != nil
            guard candidate.deletingLastPathComponent().standardizedFileURL == target.deletingLastPathComponent().standardizedFileURL,
                  candidate.standardizedFileURL == candidate.resolvingSymlinksInPath(), legacy || retry else { throw restoreConflict() }
            if exists(candidate), let digest = try? FileTree.digest(candidate, tool: tool.id, cancellation: cancellation, workspace: store.base, progress: progress), digest == expected { stage = candidate }
        }
        if stage == nil {
            guard source.standardizedFileURL == source.resolvingSymlinksInPath(),
                  try BusyInspector.inspect(paths: [source, target], tool: tool.id).isEmpty,
                  try FileTree.digest(source, tool: tool.id, cancellation: cancellation, workspace: store.base, progress: progress) == expected else { throw restoreConflict() }
            let size = FileTree.measure(source, cancellation: cancellation, progress: progress)
            guard size.isComplete, Volumes.free(at: home) > max(size.logical, size.allocated) + 536_870_912 else { throw CacheSSDError.message(L10n.text("Não há espaço confirmado para restaurar a cópia.")) }
            // Preserve the earlier staging reference, including partial copies, outside operation-*.
            try store.writeDurably(journal, name: "restore-recovery-before-\(UUID().uuidString).json")
            let fresh = target.deletingLastPathComponent().appendingPathComponent(".CacheSSD-restore-recovery-\(journal.id.uuidString)-\(UUID().uuidString)")
            journal.staging = fresh.path
            try update(&journal, phase: .copying)
            try FileTree.copy(source, to: fresh, tool: tool.id, cancellation: cancellation, progress: progress)
            guard try FileTree.digest(fresh, tool: tool.id, cancellation: cancellation, workspace: store.base, progress: progress) == expected,
                  try FileTree.digest(source, tool: tool.id, cancellation: cancellation, workspace: store.base, progress: progress) == expected else { throw restoreConflict() }
            stage = fresh
        }
        guard let stage else { throw restoreConflict() }
        journal.destinationDigest = expected
        try update(&journal, phase: .copyVerified)
        guard !cancellation.isCancelled, try BusyInspector.inspect(paths: [target], tool: tool.id).isEmpty else { throw restoreConflict() }
        try update(&journal, phase: .publishing)
        try RestorePublication.publish(stage, to: target, journal: &journal, store: store)
        try update(&journal, phase: .published)
        try finishRestoreConfiguration(&journal, tool: tool, target: target, expected: expected, cancellation: cancellation, progress: progress)
    }

    private func finishRestoreConfiguration(_ journal: inout OperationJournal, tool: CacheDescriptor, target: URL, expected: String, cancellation: CancellationFlag, progress: @escaping (String) -> Void) throws {
        guard !cancellation.isCancelled, try BusyInspector.inspect(paths: [target], tool: tool.id).isEmpty,
              try FileTree.digest(target, tool: tool.id, cancellation: cancellation, workspace: store.base, progress: progress) == expected else { throw restoreConflict() }
        var latest = try restoreSettings()
        if let location = latest.locations[tool.id] {
            guard locationMatches(location, journal: journal, tool: tool, settings: latest) else { throw restoreConflict() }
            latest.locations.removeValue(forKey: tool.id)
            try store.save(latest)
        }
        journal.detail = "Restauração local concluída; cópias anteriores preservadas"
        try update(&journal, phase: .resolved)
        try store.append(OperationRecord(title: "Cache restaurado", detail: journal.detail, recoveryPath: target.path))
    }

    public func keepCopiesAndResolve(id: UUID) throws {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        guard var journal = store.operations().first(where: { $0.id == id }), journal.schemaVersion == 1, supportedKinds.contains(journal.kind) else { throw CacheSSDError.message(L10n.text("Registro não encontrado.")) }
        if journal.kind == "restore" { _ = try restoreTarget(journal) }
        journal.phase = .resolved; journal.updatedAt = Date(); journal.detail = "Registro encerrado após revisão; nenhuma cópia foi removida"
        try store.writeDurably(journal, name: "operation-\(id.uuidString).json")
    }

    private func validateSource(_ journal: OperationJournal, source: URL) throws {
        guard source.standardizedFileURL == source.resolvingSymlinksInPath() else { throw CacheSSDError.message(L10n.text("A origem contém um caminho redirecionado.")) }
        if let toolID = journal.toolID {
            guard CacheCatalog.find(toolID, home: home)?.source == source else { throw CacheSSDError.message(L10n.text("A origem não corresponde ao cache reconhecido.")) }
        } else if let reason = PersonalActionPolicy.reasonPreventing(source, home: home) { throw CacheSSDError.message(reason) }
    }
}

/// Shared normal/recovery publication; even an empty prior local directory is retained.
enum RestorePublication {
    static func publish(_ staging: URL, to target: URL, journal: inout OperationJournal, store: Store) throws {
        let fm = FileManager.default
        var info = stat(), backup: URL?
        if lstat(target.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFDIR,
                  (try fm.contentsOfDirectory(atPath: target.path)).isEmpty else { throw CacheSSDError.message(L10n.text("Já existe cache local. Use somente o Mac para preservá-lo; ele não será sobrescrito.")) }
            let identity = try FileIdentity(target)
            let retained = target.deletingLastPathComponent().appendingPathComponent(".CacheSSD-restore-empty-\(journal.id.uuidString)-\(UUID().uuidString)")
            if journal.quarantine != nil { try store.writeDurably(journal, name: "restore-recovery-before-\(UUID().uuidString).json") }
            journal.quarantine = retained.path; journal.updatedAt = Date()
            try store.writeDurably(journal, name: "operation-\(journal.id.uuidString).json")
            try FileTree.publishWithoutReplacing(target, to: retained)
            backup = retained
            do {
                guard try FileIdentity(retained) == identity, (try fm.contentsOfDirectory(atPath: retained.path)).isEmpty else { throw CacheSSDError.message(L10n.text("O cache local mudou durante a publicação. Os arquivos foram preservados.")) }
            } catch {
                try? FileTree.publishWithoutReplacing(retained, to: target)
                throw error
            }
        } else if errno != ENOENT { throw CacheSSDError.message(L10n.text("O cache local não está disponível para uma publicação segura.")) }
        do { try FileTree.publishWithoutReplacing(staging, to: target) }
        catch {
            if let backup { try? FileTree.publishWithoutReplacing(backup, to: target) }
            throw error
        }
    }
}
