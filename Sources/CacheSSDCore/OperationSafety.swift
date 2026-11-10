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
    public init(kind: String, source: URL, destination: URL? = nil, toolID: String? = nil, id: UUID = UUID()) throws {
        schemaVersion = 1; self.id = id; self.kind = kind; self.toolID = toolID
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
    public init(store: Store, kind: String, source: URL, destination: URL? = nil, toolID: String? = nil, id: UUID = UUID(), checkpoint: @escaping (OperationJournal) throws -> Void = { _ in }) throws {
        self.store = store; self.checkpoint = checkpoint
        journal = try OperationJournal(kind: kind, source: source, destination: destination, toolID: toolID, id: id)
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

public struct RecoveryAssessment: Identifiable, Sendable {
    public let journal: OperationJournal
    public var id: UUID { journal.id }
    public let canRestoreSource: Bool
    public let explanation: String
}

public final class RecoveryManager {
    private let store: Store
    private let home: URL
    public init(store: Store = Store(), home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.store = store; self.home = home }

    public func pending() -> [RecoveryAssessment] {
        store.operations().filter(\.isPending).map { journal in
            guard journal.schemaVersion == 1 else { return RecoveryAssessment(journal: journal, canRestoreSource: false, explanation: "Registro de uma versão mais recente. Preserve as cópias e atualize o aplicativo.") }
            let source = URL(fileURLWithPath: journal.source)
            if FileManager.default.fileExists(atPath: source.path) {
                return RecoveryAssessment(journal: journal, canRestoreSource: false, explanation: "A origem continua disponível. Revise as cópias antes de encerrar este registro.")
            }
            let candidates = [journal.quarantine, journal.trashPath, journal.destination].compactMap { $0 }
            let available = candidates.contains { FileManager.default.fileExists(atPath: $0) }
            return RecoveryAssessment(journal: journal, canRestoreSource: available, explanation: available ? "Existe uma cópia de recuperação. Revise antes de restaurar a origem." : "A origem pode estar na Lixeira ou no SSD desconectado. Conecte o disco ou use a Lixeira do Finder; não remova cópias parciais.")
        }
    }

    /// Restores into an absent source only; no destination is ever overwritten.
    public func restoreSource(id: UUID, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (String) -> Void = { _ in }) throws {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        guard var journal = store.operations().first(where: { $0.id == id }), journal.isPending, journal.schemaVersion == 1 else { throw CacheSSDError.message(L10n.text("O registro de recuperação não está disponível.")) }
        let source = URL(fileURLWithPath: journal.source)
        try validateSource(journal, source: source)
        guard !FileManager.default.fileExists(atPath: source.path) else { throw CacheSSDError.message(L10n.text("A origem já existe e não será sobrescrita.")) }
        let quarantine = journal.quarantine.map { URL(fileURLWithPath: $0) }
        if let quarantine, FileManager.default.fileExists(atPath: quarantine.path) {
            guard quarantine.deletingLastPathComponent() == source.deletingLastPathComponent(),
                  quarantine.lastPathComponent == ".CacheSSD-\(journal.id.uuidString)" else { throw CacheSSDError.message(L10n.text("O caminho de recuperação não corresponde a esta operação.")) }
            guard let digest = journal.sourceDigest, try FileTree.digest(quarantine, tool: journal.toolID ?? "", cancellation: cancellation, workspace: store.base, progress: progress) == digest else {
                throw CacheSSDError.message(L10n.text("A origem em recuperação está incompleta. Preserve-a e revise a cópia no SSD."))
            }
            try FileManager.default.moveItem(at: quarantine, to: source)
        } else {
            let availableTrash = journal.trashPath.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            guard let path = availableTrash ?? journal.destination, let expected = availableTrash == nil ? journal.destinationDigest : journal.sourceDigest else {
                throw CacheSSDError.message(L10n.text("Conecte a cópia verificada ou recupere o item na Lixeira do Finder."))
            }
            let copy = URL(fileURLWithPath: path)
            guard copy.standardizedFileURL == copy.resolvingSymlinksInPath(),
                  try BusyInspector.inspect(paths: [copy]).isEmpty else { throw CacheSSDError.message(L10n.text("A cópia está indisponível, redirecionada ou em uso.")) }
            guard try FileTree.digest(copy, tool: journal.toolID ?? "", cancellation: cancellation, workspace: store.base, progress: progress) == expected else { throw CacheSSDError.message(L10n.text("A cópia mudou. Ela foi preservada para revisão manual.")) }
            let size = FileTree.measure(copy)
            guard size.isComplete, Volumes.free(at: source.deletingLastPathComponent()) > size.logical + 536_870_912 else { throw CacheSSDError.message(L10n.text("Não há espaço confirmado para restaurar a cópia.")) }
            let temp = source.deletingLastPathComponent().appendingPathComponent(".CacheSSD-recovery-\(journal.id.uuidString)")
            guard !FileManager.default.fileExists(atPath: temp.path) else { throw CacheSSDError.message(L10n.text("Há uma restauração parcial. Revise-a antes de tentar novamente.")) }
            journal.staging = temp.path
            try store.writeDurably(journal, name: "operation-\(id.uuidString).json")
            try FileTree.copyItem(copy, to: temp, tool: journal.toolID ?? "", cancellation: cancellation, progress: progress)
            guard try FileTree.digest(temp, tool: journal.toolID ?? "", cancellation: cancellation, workspace: store.base, progress: progress) == expected,
                  !FileManager.default.fileExists(atPath: source.path) else { throw CacheSSDError.message(L10n.text("A restauração mudou ou a origem reapareceu. As cópias foram mantidas.")) }
            try FileManager.default.moveItem(at: temp, to: source)
        }
        journal.phase = .resolved; journal.updatedAt = Date(); journal.detail = "Origem restaurada; cópias de recuperação preservadas"
        try store.writeDurably(journal, name: "operation-\(id.uuidString).json")
        try store.append(OperationRecord(title: "Origem recuperada", detail: journal.detail, recoveryPath: source.path))
    }

    public func keepCopiesAndResolve(id: UUID) throws {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        guard var journal = store.operations().first(where: { $0.id == id }), journal.schemaVersion == 1 else { throw CacheSSDError.message(L10n.text("Registro não encontrado.")) }
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
