import Foundation
import AppKit
import Darwin

public enum PersonalActionPolicy {
    public static func reasonPreventing(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let item = url.standardizedFileURL
        guard item == item.resolvingSymlinksInPath() else { return "Links e caminhos redirecionados ficam fora das ações automáticas." }
        var metadata = stat()
        if lstat(item.path, &metadata) == 0, metadata.st_flags & UInt32(SF_DATALESS) != 0 { return "Há conteúdo da nuvem ainda não baixado. A origem será preservada." }
        let roots = ["Downloads", "Documents", "Desktop", "Movies", "Music", "Pictures"].map { home.appendingPathComponent($0) }
        guard roots.contains(where: { item != $0 && Paths.contains(item, in: $0) }) else { return "Ações de arquivos estão disponíveis dentro das suas pastas pessoais. Dados de aplicativos usam integrações específicas." }
        let forbidden: Set<String> = ["Library", ".git", "node_modules", ".npm", ".gradle", ".android", ".codex"]
        guard !item.pathComponents.contains(where: { forbidden.contains($0) }) else { return "Este item pertence a uma ferramenta ou a dados de aplicativo." }
        let packages: Set<String> = ["app", "photoslibrary", "photolibrary", "sparsebundle", "pvm", "utm", "vmwarevm", "framework"]
        guard !item.pathComponents.contains(where: { packages.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) else { return "Bibliotecas e pacotes precisam de um procedimento específico." }
        if let values = try? item.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current { return "Baixe este arquivo no Finder antes de movê-lo. O DiskWing não baixa conteúdo da nuvem." }
        return nil
    }
    public static func validateTree(_ source: URL, home: URL, cancellation: CancellationFlag, maxEntries: Int = 1_000_000, progress: (String) -> Void = { _ in }) throws {
        if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
        guard maxEntries > 0 else { throw CacheSSDError.message(L10n.text("A inspeção excedeu o limite de itens. A origem foi preservada.")) }
        if let reason = reasonPreventing(source, home: home) { throw CacheSSDError.message(reason) }
        if try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true { return }
        var failed = false
        guard let e = FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in failed = true; return false }) else { throw CacheSSDError.message(L10n.text("Não foi possível examinar todo o conteúdo. A origem foi preservada.")) }
        var finished = false, count = 0
        while !finished {
            try autoreleasepool {
                for _ in 0..<256 {
                    if cancellation.isCancelled { throw CacheSSDError.message(L10n.text("Operação cancelada; origem preservada.")) }
                    guard let child = e.nextObject() as? URL else { finished = true; break }
                    guard count < maxEntries else { throw CacheSSDError.message(L10n.text("A inspeção excedeu o limite de itens. A origem foi preservada.")) }
                    if let reason = reasonPreventing(child, home: home) { throw CacheSSDError.message(reason) }
                    count += 1
                    if count % 200 == 0 { progress("Inspecionando \(count) itens…") }
                }
            }
        }
        if failed { throw CacheSSDError.message(L10n.text("Não foi possível examinar todo o conteúdo. A origem foi preservada.")) }
    }
}

public final class PersonalActions {
    private let home: URL
    private let store: Store
    private let trashHandler: (URL) throws -> URL?
    private let freeBytes: (URL) -> Int64
    private let busyCheck: BusyCheck
    private let checkpoint: (OperationJournal) throws -> Void
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, store: Store = Store(),
                freeBytes: @escaping (URL) -> Int64 = { Volumes.free(at: $0) },
                trashHandler: @escaping (URL) throws -> URL? = { url in
                    var result: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                    return result.map { $0 as URL }
                }, busyCheck: @escaping BusyCheck = { try BusyInspector.inspect(paths: $0, tool: $1) },
                checkpoint: @escaping (OperationJournal) throws -> Void = { _ in }) {
        self.home = home; self.store = store; self.freeBytes = freeBytes
        self.trashHandler = trashHandler; self.busyCheck = busyCheck; self.checkpoint = checkpoint
    }
    public func trash(_ source: URL, expectedIdentity: FileIdentity? = nil, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (String) -> Void = { _ in }) throws -> OperationRecord {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        if let expectedIdentity, try FileIdentity(source) != expectedIdentity { throw CacheSSDError.message(L10n.text("O item mudou desde a análise. Analise novamente antes de confirmar.")) }
        try PersonalActionPolicy.validateTree(source, home: home, cancellation: cancellation, progress: progress)
        guard try busyCheck([source], nil).isEmpty else { throw CacheSSDError.message(L10n.text("O item está em uso.")) }
        let operation = try OperationContext(store: store, kind: "trash", source: source, checkpoint: checkpoint)
        do {
            if let expectedIdentity, operation.journal.sourceIdentity != expectedIdentity { throw CacheSSDError.message(L10n.text("O item mudou desde a análise. Analise novamente antes de confirmar.")) }
            try operation.advance(.verifying)
            progress("Conferindo a origem…")
            let digest = try FileTree.digest(source, cancellation: cancellation, workspace: store.base, progress: progress)
            operation.journal.sourceDigest = digest
            try operation.advance(.trashing)
            // Process inspection can be slow; source checks must follow it.
            guard !cancellation.isCancelled, try busyCheck([source], nil).isEmpty else { throw CacheSSDError.message(L10n.text("A origem mudou ou a operação foi cancelada.")) }
            try operation.assertSourceIdentity()
            guard !cancellation.isCancelled, try FileTree.digest(source, cancellation: cancellation, workspace: store.base, progress: progress) == digest,
                  !cancellation.isCancelled else { throw CacheSSDError.message(L10n.text("A origem mudou ou a operação foi cancelada.")) }
            let result = try trashHandler(source)
            operation.journal.trashPath = result?.path
            try operation.advance(.published)
            let record = OperationRecord(title: "Item enviado à Lixeira", detail: "\(source.lastPathComponent). O espaço só será liberado quando você esvaziar a Lixeira no Finder.", recoveryPath: result?.path)
            try store.append(record)
            try operation.advance(.completed)
            return record
        } catch { operation.recordFailure(error, cancellation: cancellation); throw error }
    }
    public func move(_ source: URL, to directory: URL, expectedIdentity: FileIdentity? = nil, cancellation: CancellationFlag = CancellationFlag(), progress: @escaping (String) -> Void = { _ in }) throws -> OperationRecord {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        if let expectedIdentity, try FileIdentity(source) != expectedIdentity { throw CacheSSDError.message(L10n.text("O item mudou desde a análise. Analise novamente antes de confirmar.")) }
        try PersonalActionPolicy.validateTree(source, home: home, cancellation: cancellation, progress: progress)
        guard directory.standardizedFileURL == directory.resolvingSymlinksInPath(), !Paths.contains(directory, in: source) else { throw CacheSSDError.message(L10n.text("Escolha uma pasta independente e sem links.")) }
        try FileTree.validateDestination(directory)
        let final = directory.appendingPathComponent(source.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: final.path) else { throw CacheSSDError.message(L10n.text("Já existe um item com esse nome. Nada foi sobrescrito.")) }
        guard try busyCheck([source], nil).isEmpty else { throw CacheSSDError.message(L10n.text("O item está em uso.")) }
        let size = FileTree.measure(source, cancellation: cancellation, progress: progress)
        guard size.isComplete else { throw CacheSSDError.message(L10n.text("A leitura da origem está incompleta.")) }
        guard freeBytes(directory) > max(size.logical, size.allocated) + 536_870_912 else { throw CacheSSDError.message(L10n.text("O destino não tem espaço confirmado para a cópia e a margem de segurança.")) }
        let operation = try OperationContext(store: store, kind: "personalMove", source: source, destination: final, checkpoint: checkpoint)
        let staging = directory.appendingPathComponent(".CacheSSD-move-\(operation.journal.id.uuidString)")
        operation.journal.staging = staging.path
        do {
            if let expectedIdentity, operation.journal.sourceIdentity != expectedIdentity { throw CacheSSDError.message(L10n.text("O item mudou desde a análise. Analise novamente antes de confirmar.")) }
            try operation.advance(.verifying)
            let digest = try FileTree.digest(source, cancellation: cancellation, workspace: directory, progress: progress)
            operation.journal.sourceDigest = digest
            try operation.advance(.copying)
            try FileTree.copyItem(source, to: staging, cancellation: cancellation, progress: progress)
            guard try FileTree.digest(staging, cancellation: cancellation, workspace: directory, progress: progress) == digest,
                  try FileTree.digest(source, cancellation: cancellation, workspace: directory, progress: progress) == digest else { throw CacheSSDError.message(L10n.text("A cópia ou os metadados mudaram; origem preservada.")) }
            operation.journal.destinationDigest = digest
            try operation.advance(.copyVerified)
            try operation.assertSourceIdentity()
            guard !cancellation.isCancelled, try busyCheck([source], nil).isEmpty else { throw CacheSSDError.message(L10n.text("A origem passou a ser utilizada ou a cópia foi cancelada.")) }
            try operation.advance(.publishing)
            guard !FileManager.default.fileExists(atPath: final.path) else { throw CacheSSDError.message(L10n.text("O destino passou a existir; nada foi sobrescrito.")) }
            try FileManager.default.moveItem(at: staging, to: final)
            try operation.advance(.published)
            try operation.assertSourceIdentity()
            guard try FileTree.digest(source, cancellation: cancellation, workspace: directory, progress: progress) == digest else { throw CacheSSDError.message(L10n.text("A origem mudou após a cópia; ambas foram preservadas.")) }
            try operation.advance(.trashing)
            // Process inspection can be slow; source checks must follow it.
            guard !cancellation.isCancelled, try busyCheck([source], nil).isEmpty else { throw CacheSSDError.message(L10n.text("A origem passou a ser utilizada ou a cópia foi cancelada.")) }
            try operation.assertSourceIdentity()
            guard !cancellation.isCancelled, try FileTree.digest(source, cancellation: cancellation, workspace: directory, progress: progress) == digest,
                  !cancellation.isCancelled else { throw CacheSSDError.message(L10n.text("A origem mudou após a cópia; ambas foram preservadas.")) }
            operation.journal.trashPath = try trashHandler(source)?.path
            try operation.advance(.completed, detail: "Cópia e metadados conferidos; origem na Lixeira")
            let record = OperationRecord(title: "Arquivo copiado e origem na Lixeira", detail: "Cópia conferida em \(final.path). Revise a Lixeira no Finder antes de liberar o espaço da origem.", recoveryPath: final.path)
            try store.append(record); return record
        } catch { operation.recordFailure(error, cancellation: cancellation); throw error }
    }
}
