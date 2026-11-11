import Foundation
import AppKit
import CryptoKit
import Darwin

public enum GraphicalCachePhase: String, Codable, Sendable {
    case preparing, copying, copyVerified, redirecting, waitingForUsage, releasing, completed
    case restoring, restored, interrupted, cancelled
}

private extension GraphicalCacheMigrationEngine {
    func transferImpl(candidate: GraphicalCacheCandidate, volume: VolumeInfo, releaseSource: Bool,
                      cancellation: CancellationFlag, progress: @escaping (CacheTransferProgress) -> Void) throws -> CacheTransferItemResult {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        try requireCandidate(candidate)
        try requireScope([home, store.base, candidate.sourceURL, URL(fileURLWithPath: volume.path)])
        guard store.pendingConfigurationRecords().isEmpty, try pendingTransfers().isEmpty else { throw failure("Há uma transferência ou configuração interrompida que precisa de revisão.") }
        var registry = try readRegistry()
        guard registry.active[candidate.id] == nil else { throw failure("Este cache já tem um destino. Revise seu estado antes de transferir novamente.") }
        try requireClosed(candidate)
        let volumeRoot = try requireVolume(volume)
        let rootIdentity = try FileIdentity(volumeRoot)
        let source = home.appendingPathComponent(GraphicalCacheCatalog.chromeRelativePath)
        let sourceParent = try GraphicalCacheFiles.openParent(of: source, under: home, create: true)
        defer { close(sourceParent) }
        try GraphicalCacheFiles.assertParent(sourceParent, matches: source.deletingLastPathComponent())
        guard source.standardizedFileURL.path == source.resolvingSymlinksInPath().standardizedFileURL.path else { throw failure("O cache local já foi redirecionado e será preservado.") }
        let measurement = FileTree.measure(source, cancellation: cancellation)
        let sourceDirectoryIdentity = measurement.missing ? nil : try GraphicalCacheDirectoryIdentity(source)
        guard measurement.missing || measurement.isComplete else { throw failure("A leitura deste cache está incompleta. A origem será preservada.") }
        guard !cancellation.isCancelled else { throw failure("Operação cancelada; origem preservada.") }
        let required = max(measurement.logical, measurement.allocated) + 536_870_912
        guard volume.freeBytes > required, freeBytes(volumeRoot) > required else { throw failure("O SSD não tem espaço suficiente para o cache e a margem de segurança.") }
        let id = UUID(), started = Date()
        let relative = "MacCaches/CacheSSD/\(registry.installationID)/graphical/\(candidate.id)/\(id.uuidString)/data"
        let destination = volumeRoot.appendingPathComponent(relative)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".partial-data")
        let quarantine = source.deletingLastPathComponent().appendingPathComponent(".DiskWing-cache-\(id.uuidString)")
        var journal = GraphicalCacheJournal(schemaVersion: 1, id: id, candidateID: candidate.id, sourceURL: source,
                                           volumeUUID: volume.uuid, relativeDestination: relative,
                                           sourceIdentity: measurement.missing ? nil : try FileIdentity(source), sourceDigest: nil,
                                           sourceQuarantine: measurement.missing ? nil : quarantine, stagingURL: staging,
                                           phase: .preparing, detail: "Origem preservada", registration: nil, startedAt: started, updatedAt: started)
        try saveJournal(&journal, phase: .preparing)
        var configuration = ConfigurationChange(source: store.base.appendingPathComponent(registryName).path,
                                                before: try encoded(registry), after: try encoded(journal))
        try store.writeDurably(configuration, name: configurationName(id))
        var metadataProof: GraphicalCacheVerificationProof?
        do {
            try requireClosed(candidate); try requireUnchangedVolume(volume, identity: rootIdentity)
            try GraphicalCacheFiles.createDirectory(staging.deletingLastPathComponent(), under: volumeRoot)
            if measurement.missing { try GraphicalCacheFiles.createDirectory(staging, under: volumeRoot) }
            try requireUnchangedVolume(volume, identity: rootIdentity)
            if !measurement.missing {
                progress(CacheTransferProgress(entryID: candidate.id, state: .transferring, detail: "Conferindo o cache original…"))
                journal.sourceDigest = try FileTree.digest(source, cancellation: cancellation, workspace: destination.deletingLastPathComponent())
                try saveJournal(&journal, phase: .copying)
                try requireCanonical(staging); try requireClosed(candidate)
                try FileTree.copy(source, to: staging, cancellation: cancellation) { text in
                    progress(CacheTransferProgress(entryID: candidate.id, state: .transferring, detail: text))
                }
                let reference = destination.deletingLastPathComponent().appendingPathComponent(".DiskWing-os-copy-reference-" + id.uuidString)
                try GraphicalCacheFiles.createDirectory(reference, under: volumeRoot)
                metadataProof = try GraphicalCacheVerification.verify(source: source, target: staging, sourceAnchor: home, targetAnchor: volumeRoot,
                    expectedSource: try requireSourceIdentity(sourceDirectoryIdentity), expectedTarget: GraphicalCacheDirectoryIdentity(staging),
                    referenceRoot: reference, referenceAnchor: volumeRoot, cancellation: cancellation)
                journal.metadataVerification = metadataProof
                guard try FileTree.digest(source, cancellation: cancellation, workspace: destination.deletingLastPathComponent()) == journal.sourceDigest,
                      try FileIdentity(source) == journal.sourceIdentity else { throw failure("O cache mudou durante a cópia. A origem e as cópias foram preservadas.") }
            }
            try saveJournal(&journal, phase: .copyVerified)
            try requireUnchangedVolume(volume, identity: rootIdentity); try requireClosed(candidate)
            guard !cancellation.isCancelled else { throw failure("Operação cancelada; origem preservada.") }
            try requireCanonical(staging); try requireCanonical(destination)
            try FileTree.publishWithoutReplacing(staging, to: destination)
            journal.stagingURL = nil
            let baseline = try GraphicalCacheActivity.fingerprint(destination, cancellation: cancellation)
            let parent = try GraphicalCacheFiles.openParent(of: source, under: home, create: true)
            defer { close(parent) }
            let temporaryLink = ".DiskWing-link-" + id.uuidString
            guard symlinkat(destination.path, parent, temporaryLink) == 0 else { throw failure("Não foi possível preparar o direcionamento deste cache.") }
            var preparedLink = stat()
            guard fstatat(parent, temporaryLink, &preparedLink, AT_SYMLINK_NOFOLLOW) == 0, preparedLink.st_mode & S_IFMT == S_IFLNK else { throw failure("O direcionamento do cache não pôde ser confirmado.") }
            var registration = GraphicalCacheRegistration(id: id, candidateID: candidate.id, applicationID: candidate.applicationID,
                applicationName: candidate.applicationName, applicationVersion: candidate.applicationVersion ?? "simulated",
                applicationURL: candidate.applicationURL, sourceURL: source, volumeUUID: volume.uuid, relativeDestination: relative,
                linkTarget: destination.path, linkDevice: Int64(preparedLink.st_dev), linkInode: UInt64(preparedLink.st_ino),
                sourceQuarantine: journal.sourceQuarantine, sourceDigest: journal.sourceDigest,
                sourceLogicalBytes: measurement.logical, sourceAllocatedBytes: measurement.allocated,
                releaseSourceAfterVerifiedUse: releaseSource, sourceReleased: measurement.missing,
                state: .configuredNeedsReopen, baselineFingerprint: baseline, evidence: nil,
                isSimulated: candidate.isSimulated, createdAt: started, updatedAt: Date())
            registration.volumeIdentity = try GraphicalCacheDirectoryIdentity(volumeRoot)
            registration.destinationIdentity = try GraphicalCacheDirectoryIdentity(destination)
            registration.metadataVerification = metadataProof
            journal.registration = registration
            try saveJournal(&journal, phase: .redirecting)
            try requireUnchangedVolume(volume, identity: rootIdentity); try requireClosed(candidate)
            try GraphicalCacheFiles.assertParent(parent, matches: source.deletingLastPathComponent())
            if let original = journal.sourceIdentity {
                guard try FileIdentity(source) == original,
                      try FileTree.digest(source, cancellation: cancellation, workspace: destination.deletingLastPathComponent()) == journal.sourceDigest else { throw failure("O cache mudou antes da ativação. A origem foi preservada.") }
                guard renameatx_np(parent, source.lastPathComponent, parent, quarantine.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw failure("Não foi possível preservar o cache original para recuperação.") }
                try GraphicalCacheFiles.assertParent(parent, matches: source.deletingLastPathComponent())
                try requireClosed(candidate)
                guard try FileIdentity(quarantine) == original else { throw failure("O cache original foi substituído e foi preservado para revisão.") }
            }
            guard renameatx_np(parent, temporaryLink, parent, source.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw failure("O caminho do cache reapareceu. Nada foi sobrescrito; revise a recuperação.") }
            var link = stat()
            guard fstatat(parent, source.lastPathComponent, &link, AT_SYMLINK_NOFOLLOW) == 0, link.st_mode & S_IFMT == S_IFLNK else { throw failure("O direcionamento do cache não pôde ser confirmado.") }
            guard Int64(link.st_dev) == registration.linkDevice, UInt64(link.st_ino) == registration.linkInode else { throw failure("O direcionamento mudou durante a ativação. As cópias foram preservadas.") }
            journal.registration = registration
            try saveJournal(&journal, phase: .waitingForUsage)
            registry.active[candidate.id] = registration; try saveRegistry(registry)
            configuration.state = "completed"; try store.writeDurably(configuration, name: configurationName(id))
            try store.append(OperationRecord(title: "Cache de \(candidate.applicationName) preparado no SSD",
                                            detail: "Cópia conferida e destino configurado. O original fica preservado até verificar o uso do aplicativo.", recoveryPath: destination.path))
            progress(CacheTransferProgress(entryID: candidate.id, state: .configuredNeedsReopen, detail: "Reabra o aplicativo e verifique o uso do SSD."))
            return CacheTransferItemResult(id: candidate.id, state: .configuredNeedsReopen,
                                           detail: "Destino configurado. A origem ainda não foi liberada.", recordID: id,
                                           sourceReleased: registration.sourceReleased, sourceLogicalBytes: measurement.logical)
        } catch {
            journal.detail = error.localizedDescription; journal.interruptedAtPhase = journal.phase
            try? saveJournal(&journal, phase: cancellation.isCancelled ? .cancelled : .interrupted, invokeCheckpoint: false)
            throw error
        }
    }

    func verifyUsageImpl(candidate: GraphicalCacheCandidate, cancellation: CancellationFlag,
                         progress: @escaping (CacheTransferProgress) -> Void) throws -> GraphicalCacheStatus {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        var registry = try readRegistry()
        guard var registration = registry.active[candidate.id] else { return status(candidate: candidate) }
        try validate(registration)
        guard versionMatches(candidate, record: registration) else { throw failure("A versão do aplicativo mudou. Nenhum original será liberado sem nova qualificação.") }
        guard managedLinkMatches(registration) else { throw failure("O caminho deste cache mudou. As cópias foram preservadas; revise a recuperação.") }
        let destination = try self.destination(for: registration)
        guard destination.path == registration.linkTarget else { return status(registration, .configuredNeedsReopen, "O SSD mudou de nome ou montagem. Encerre o aplicativo e revise a retomada.") }
        guard !cancellation.isCancelled else { throw failure("Operação cancelada; origem preservada.") }
        let observed: GraphicalCacheUsageEvidence?
        if let usageObserver { observed = try usageObserver(candidate, destination, registration.baselineFingerprint) }
        else { observed = try GraphicalCacheActivity.observe(candidate, destination, registration.baselineFingerprint, cancellation: cancellation) }
        guard let evidence = observed,
              evidence.applicationVersion == registration.applicationVersion,
              !evidence.processIDs.isEmpty, evidence.observedReadAccess, evidence.observedWriteAccess,
              evidence.metadataFingerprint != registration.baselineFingerprint,
              evidence.metadataFingerprint == (try? GraphicalCacheActivity.fingerprint(destination, cancellation: cancellation)),
              evidence.observedAt >= registration.createdAt,
              (evidence.isSimulated ? registration.isSimulated && allowSimulatedCandidates && permittedRoot != nil : evidence.processIDs.allSatisfy({ $0 > 0 })) else {
            return status(registration, .configuredNeedsReopen, "Ainda não foi possível comprovar leitura e escrita do aplicativo no cache do SSD. O original foi preservado.")
        }
        var journal = try readRecord(GraphicalCacheJournal.self, name: journalName(registration.id))
        guard journal.schemaVersion == 1, journal.registration?.id == registration.id else { throw failure("O registro de recuperação deste cache é inválido e foi preservado.") }
        registration.evidence = evidence; registration.state = .ssdVerified; registration.updatedAt = Date()
        journal.registration = registration
        var configuration = try readRecord(ConfigurationChange.self, name: configurationName(registration.id))
        if registration.releaseSourceAfterVerifiedUse, let quarantine = registration.sourceQuarantine {
            configuration.state = "prepared"; try store.writeDurably(configuration, name: configurationName(registration.id))
            try saveJournal(&journal, phase: .releasing)
            progress(CacheTransferProgress(entryID: candidate.id, state: .transferring, detail: "Conferindo o original antes de liberar espaço…"))
            do {
                guard !cancellation.isCancelled,
                      managedLinkMatches(registration), try self.destination(for: registration).path == destination.path,
                      try busyCheck([quarantine], nil).isEmpty,
                      try FileTree.digest(quarantine, cancellation: cancellation, workspace: destination.deletingLastPathComponent()) == registration.sourceDigest else { throw failure("O original mudou ou continua em uso. Ele foi preservado.") }
                let parent = try GraphicalCacheFiles.openParent(of: quarantine, under: home, create: false)
                defer { close(parent) }
                try GraphicalCacheFiles.assertParent(parent, matches: quarantine.deletingLastPathComponent())
                guard versionMatches(candidate, record: registration), managedLinkMatches(registration),
                      try self.destination(for: registration).path == destination.path,
                      let expectedOriginal = journal.sourceIdentity else { throw failure("A identidade ou versão do cache mudou. O original foi preservado.") }
                try GraphicalCacheFiles.removeDirectory(quarantine.lastPathComponent, parent: parent, expectedIdentity: expectedOriginal, cancellation: cancellation)
                registration.sourceQuarantine = nil; registration.sourceReleased = true
            } catch {
                journal.detail = error.localizedDescription; journal.registration = registration; journal.interruptedAtPhase = journal.phase
                try? saveJournal(&journal, phase: cancellation.isCancelled ? .cancelled : .interrupted, invokeCheckpoint: false)
                throw error
            }
        }
        journal.registration = registration
        registry.active[candidate.id] = registration; try saveRegistry(registry)
        try saveJournal(&journal, phase: .completed)
        configuration.state = "completed"; try store.writeDurably(configuration, name: configurationName(registration.id))
        try store.append(OperationRecord(title: "Uso de cache de \(candidate.applicationName) no SSD comprovado",
                                        detail: registration.sourceReleased ? "Uso do SSD observado; original conferido e liberado." : "Uso do SSD observado; original local mantido por sua escolha.", recoveryPath: destination.path))
        return status(registration, .ssdVerified, registration.sourceReleased ? "Uso do cache no SSD comprovado; origem liberada." : "Uso do cache no SSD comprovado; origem local mantida.")
    }

    func requireCandidate(_ candidate: GraphicalCacheCandidate) throws {
        guard candidate.id == GraphicalCacheCatalog.chromeCacheID, candidate.applicationID == GraphicalCacheCatalog.chromeBundleID,
              GraphicalCacheFiles.normalizedSystemPath(candidate.sourceURL.path) == GraphicalCacheFiles.normalizedSystemPath(home.appendingPathComponent(GraphicalCacheCatalog.chromeRelativePath).path) else { throw failure("Este caminho não pertence a um cache gráfico qualificado.") }
        if candidate.isSimulated {
            guard allowSimulatedCandidates, permittedRoot != nil else { throw failure("Caches de amostra só podem ser usados em uma sessão isolada.") }
        } else {
            guard GraphicalCacheCatalog.platformIsQualified else { throw failure("A transferência deste cache só foi qualificada em Apple Silicon com macOS 26 e SSD APFS.") }
            guard !GraphicalCacheCatalog.chromeHasCustomStorage() else { throw failure("O Chrome usa uma configuração de cache ou perfil personalizada. Ela foi preservada.") }
            guard let app = candidate.applicationURL, let info = GenericAppDetector.readBundleInfo(app),
                  GraphicalCacheCatalog.chromeSignatureIsQualified(app),
                  info["CFBundleIdentifier"] as? String == candidate.applicationID,
                  let version = info["CFBundleShortVersionString"] as? String,
                  version == candidate.applicationVersion, GraphicalCacheCatalog.qualifiedChromeVersions.contains(version) else { throw failure("Este aplicativo ou sua versão ainda não tem uma transferência qualificada.") }
        }
        guard candidate.canTransfer else { throw failure(candidate.blockedReason ?? "Este cache ainda não tem uma transferência qualificada.") }
    }

    func restoreImpl(candidateID: String, cancellation: CancellationFlag,
                     progress: @escaping (CacheTransferProgress) -> Void) throws -> CacheTransferItemResult {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        var registry = try readRegistry()
        guard let record = registry.active[candidateID] else { throw failure("Este cache não tem um destino registrado.") }
        try validate(record)
        let candidate = candidateForRecord(record)
        try requireClosed(candidate)
        guard managedLinkMatches(record) else { throw failure("O caminho deste cache mudou. Nenhum conteúdo local será sobrescrito.") }
        let operationID = UUID(), now = Date()
        let source = record.sourceURL
        let staging = source.deletingLastPathComponent().appendingPathComponent(".DiskWing-restore-" + operationID.uuidString)
        var journal = GraphicalCacheJournal(schemaVersion: 1, id: operationID, candidateID: candidateID, sourceURL: source,
            volumeUUID: record.volumeUUID, relativeDestination: record.relativeDestination, sourceIdentity: nil,
            sourceDigest: nil, sourceQuarantine: record.sourceQuarantine, stagingURL: staging,
            phase: .preparing, detail: "Cópias preservadas", registration: record, startedAt: now, updatedAt: now)
        journal.operation = "restore"
        var configuration = ConfigurationChange(source: store.base.appendingPathComponent(registryName).path,
                                                before: try encoded(registry), after: "Restaurar cache gráfico registrado")
        try saveJournal(&journal, phase: .preparing)
        try store.writeDurably(configuration, name: configurationName(operationID))
        do {
            let currentDestination = try? destination(for: record)
            let restoreInput: URL
            if let currentDestination { restoreInput = currentDestination }
            else if let quarantine = record.sourceQuarantine, let expected = record.sourceDigest,
                    try FileTree.digest(quarantine, cancellation: cancellation, workspace: store.base) == expected {
                restoreInput = quarantine
            } else { throw failure("Conecte o SSD para restaurar este cache. Nenhuma cópia será substituída.") }
            try requireScope([source.deletingLastPathComponent(), restoreInput, staging])
            try requireCanonical(restoreInput)
            guard try busyCheck([restoreInput], nil).isEmpty else { throw failure("O cache está em uso. Encerre o aplicativo antes de restaurar.") }
            let size = FileTree.measure(restoreInput, cancellation: cancellation)
            guard size.isComplete else { throw failure("A leitura deste cache está incompleta. A origem será preservada.") }
            journal.sourceIdentity = try FileIdentity(restoreInput)
            journal.sourceDigest = try FileTree.digest(restoreInput, cancellation: cancellation, workspace: store.base)
            if currentDestination == nil {
                // The verified original is already local. Swap it back without
                // requiring another cache-sized allocation on a nearly full Mac.
                journal.publicationIdentity = journal.sourceIdentity; journal.stagingURL = nil
                journal.heldLinkName = restoreInput.lastPathComponent
                try saveJournal(&journal, phase: .restoring)
                try requireClosed(candidate)
                guard !cancellation.isCancelled, managedLinkMatches(record),
                      try FileIdentity(restoreInput) == journal.sourceIdentity,
                      try FileTree.digest(restoreInput, cancellation: cancellation, workspace: store.base) == journal.sourceDigest else { throw failure("O original mudou. Todas as cópias foram preservadas.") }
                let parent = try GraphicalCacheFiles.openParent(of: source, under: home, create: false)
                defer { close(parent) }
                try GraphicalCacheFiles.assertParent(parent, matches: source.deletingLastPathComponent())
                guard renameatx_np(parent, restoreInput.lastPathComponent, parent, source.lastPathComponent, UInt32(RENAME_SWAP)) == 0 else { throw failure("Não foi possível devolver o original local sem sobrescrever dados.") }
                try removeHeldLink(name: restoreInput.lastPathComponent, parent: parent, expected: record)
                registry.active.removeValue(forKey: candidateID); try saveRegistry(registry)
                journal.sourceQuarantine = nil
                try saveJournal(&journal, phase: .restored)
                try closePriorTransferAfterRestore(record)
                configuration.state = "completed"; try store.writeDurably(configuration, name: configurationName(operationID))
                return CacheTransferItemResult(id: candidateID, state: .none, detail: "Original local restaurado sem duplicar seus dados. A cópia no SSD foi preservada.", recordID: operationID)
            }
            guard freeBytes(home) > max(size.logical, size.allocated) + 536_870_912 else { throw failure("Não há espaço confirmado no Mac para restaurar o cache e a margem de segurança.") }
            try saveJournal(&journal, phase: .copying)
            try requireClosed(candidate); try requireCanonical(staging)
            try FileTree.copy(restoreInput, to: staging, cancellation: cancellation) { text in
                progress(CacheTransferProgress(entryID: candidateID, state: .transferring, detail: text))
            }
            let inputAnchor = URL(fileURLWithPath: try resolvedVolumePath(record.volumeUUID))
            let reference = staging.deletingLastPathComponent().appendingPathComponent(".DiskWing-os-restore-reference-" + operationID.uuidString)
            try GraphicalCacheFiles.createDirectory(reference, under: home)
            journal.metadataVerification = try GraphicalCacheVerification.verify(source: restoreInput, target: staging,
                sourceAnchor: inputAnchor, targetAnchor: home, expectedSource: GraphicalCacheDirectoryIdentity(restoreInput),
                expectedTarget: GraphicalCacheDirectoryIdentity(staging), referenceRoot: reference, referenceAnchor: home, cancellation: cancellation)
            guard try FileTree.digest(restoreInput, cancellation: cancellation, workspace: restoreInput.deletingLastPathComponent()) == journal.sourceDigest,
                  try FileIdentity(restoreInput) == journal.sourceIdentity else { throw failure("A cópia mudou durante a restauração. Todas as cópias foram preservadas.") }
            journal.publicationIdentity = try FileIdentity(staging)
            journal.heldLinkName = ".DiskWing-restored-link-" + operationID.uuidString
            if let original = record.sourceQuarantine { journal.preservedRecoveryURLs = [original] }
            try saveJournal(&journal, phase: .restoring)
            guard !cancellation.isCancelled, managedLinkMatches(record) else { throw failure("O cache mudou ou a restauração foi cancelada. As cópias foram preservadas.") }
            try requireClosed(candidate)
            let parent = try GraphicalCacheFiles.openParent(of: source, under: home, create: false)
            defer { close(parent) }
            try GraphicalCacheFiles.assertParent(parent, matches: source.deletingLastPathComponent())
            let heldLink = ".DiskWing-restored-link-" + operationID.uuidString
            guard renameatx_np(parent, source.lastPathComponent, parent, heldLink, UInt32(RENAME_EXCL)) == 0 else { throw failure("O direcionamento mudou antes da restauração. Ele foi preservado.") }
            guard renameatx_np(parent, staging.lastPathComponent, parent, source.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw failure("O cache local reapareceu. Nada foi sobrescrito; revise a recuperação.") }
            try removeHeldLink(name: heldLink, parent: parent, expected: record)
            registry.active.removeValue(forKey: candidateID); try saveRegistry(registry)
            journal.stagingURL = nil
            try saveJournal(&journal, phase: .restored)
            try closePriorTransferAfterRestore(record)
            configuration.state = "completed"; try store.writeDurably(configuration, name: configurationName(operationID))
            try store.append(OperationRecord(title: "Cache de \(record.applicationName) restaurado no Mac",
                                            detail: "Cópia conferida no Mac. Cópias anteriores no SSD e na recuperação foram preservadas.", recoveryPath: restoreInput.path))
            return CacheTransferItemResult(id: candidateID, state: .none, detail: "Cache restaurado no Mac; cópias anteriores preservadas.", recordID: operationID)
        } catch {
            journal.detail = error.localizedDescription; journal.interruptedAtPhase = journal.phase
            try? saveJournal(&journal, phase: cancellation.isCancelled ? .cancelled : .interrupted, invokeCheckpoint: false)
            throw error
        }
    }

    func resumeImpl(candidateID: String, cancellation: CancellationFlag,
                    progress: @escaping (CacheTransferProgress) -> Void) throws -> CacheTransferItemResult {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        var registry = try readRegistry()
        guard var record = registry.active[candidateID] else { throw failure("Este cache não tem um destino registrado.") }
        try validate(record)
        let candidate = candidateForRecord(record)
        guard versionMatches(candidate, record: record) else { throw failure("A versão do aplicativo mudou. Revise o cache antes de retomar o SSD.") }
        try requireClosed(candidate)
        guard managedLinkMatches(record) else { throw failure("O aplicativo recriou ou alterou o cache local. Ele foi preservado; não há mesclagem automática.") }
        let destination = try self.destination(for: record, allowRemount: true)
        let id = UUID(), now = Date()
        var journal = GraphicalCacheJournal(schemaVersion: 1, id: id, candidateID: candidateID, sourceURL: record.sourceURL,
            volumeUUID: record.volumeUUID, relativeDestination: record.relativeDestination, sourceIdentity: nil,
            sourceDigest: nil, sourceQuarantine: record.sourceQuarantine, stagingURL: nil,
            phase: .preparing, detail: "Gerações preservadas; sem mesclagem", registration: record, startedAt: now, updatedAt: now)
        journal.operation = "resume"
        var configuration = ConfigurationChange(source: store.base.appendingPathComponent(registryName).path,
                                                before: try encoded(registry), after: "Retomar cache gráfico no SSD sem mesclagem")
        try saveJournal(&journal, phase: .preparing)
        try store.writeDurably(configuration, name: configurationName(id))
        do {
            guard !cancellation.isCancelled else { throw failure("Operação cancelada; origem preservada.") }
            if destination.path != record.linkTarget {
                let parent = try GraphicalCacheFiles.openParent(of: record.sourceURL, under: home, create: false)
                defer { close(parent) }
                let temporary = ".DiskWing-resume-link-" + id.uuidString
                guard symlinkat(destination.path, parent, temporary) == 0 else { throw failure("Não foi possível preparar a retomada do SSD.") }
                try saveJournal(&journal, phase: .redirecting)
                try requireClosed(candidate)
                guard managedLinkMatches(record) else { throw failure("O direcionamento mudou e foi preservado para revisão.") }
                try GraphicalCacheFiles.assertParent(parent, matches: record.sourceURL.deletingLastPathComponent())
                guard renameatx_np(parent, temporary, parent, record.sourceURL.lastPathComponent, UInt32(RENAME_SWAP)) == 0 else { throw failure("Não foi possível retomar o SSD sem substituir dados desconhecidos.") }
                try removeHeldLink(name: temporary, parent: parent, expected: record)
                var link = stat()
                guard fstatat(parent, record.sourceURL.lastPathComponent, &link, AT_SYMLINK_NOFOLLOW) == 0,
                      link.st_mode & S_IFMT == S_IFLNK else { throw failure("O direcionamento do cache não pôde ser confirmado.") }
                record.linkTarget = destination.path; record.linkDevice = Int64(link.st_dev); record.linkInode = UInt64(link.st_ino)
            }
            record.state = .configuredNeedsReopen; record.evidence = nil
            record.volumeIdentity = try volumeProvider(record.volumeUUID).map { try GraphicalCacheDirectoryIdentity(URL(fileURLWithPath: $0.path)) }
            record.destinationIdentity = try GraphicalCacheDirectoryIdentity(destination)
            record.baselineFingerprint = try GraphicalCacheActivity.fingerprint(destination, cancellation: cancellation); record.updatedAt = Date()
            registry.active[candidateID] = record; try saveRegistry(registry)
            var original = try readRecord(GraphicalCacheJournal.self, name: journalName(record.id))
            original.registration = record; try saveJournal(&original, phase: .waitingForUsage)
            journal.registration = record; try saveJournal(&journal, phase: .completed)
            configuration.state = "completed"; try store.writeDurably(configuration, name: configurationName(id))
            progress(CacheTransferProgress(entryID: candidateID, state: .configuredNeedsReopen, detail: "Reabra o aplicativo para voltar ao cache do SSD."))
            return CacheTransferItemResult(id: candidateID, state: .configuredNeedsReopen, detail: "Destino retomado sem mesclar caches. Reabra o aplicativo e verifique o uso.", recordID: record.id, sourceReleased: record.sourceReleased, sourceLogicalBytes: record.sourceLogicalBytes)
        } catch {
            journal.detail = error.localizedDescription; journal.interruptedAtPhase = journal.phase
            try? saveJournal(&journal, phase: cancellation.isCancelled ? .cancelled : .interrupted, invokeCheckpoint: false)
            throw error
        }
    }

    func recoverImpl(operationID: UUID, cancellation: CancellationFlag,
                     progress: @escaping (CacheTransferProgress) -> Void) throws -> CacheTransferItemResult {
        let lease = try OperationLease(store: store); defer { withExtendedLifetime(lease) {} }
        var journal = try readRecord(GraphicalCacheJournal.self, name: journalName(operationID))
        guard !journal.isUnsupported, journal.candidateID == GraphicalCacheCatalog.chromeCacheID,
              journal.operation == nil || ["restore", "resume"].contains(journal.operation ?? ""),
              GraphicalCacheFiles.normalizedSystemPath(journal.sourceURL.path) == GraphicalCacheFiles.normalizedSystemPath(home.appendingPathComponent(GraphicalCacheCatalog.chromeRelativePath).path) else { throw failure("O registro deste cache não corresponde a uma pasta qualificada.") }
        var registry = try readRegistry()
        let record = journal.registration ?? registry.active[journal.candidateID]
        let candidate = record.map(candidateForRecord) ?? GraphicalCacheCandidate(id: journal.candidateID, applicationID: GraphicalCacheCatalog.chromeBundleID,
            applicationName: "Google Chrome", applicationVersion: nil, applicationURL: nil, sourceURL: journal.sourceURL,
            scopeLabel: "Diretório de caches do Chrome", canTransfer: false)
        try requireClosed(candidate)
        guard !cancellation.isCancelled else { throw failure("Operação cancelada; origem preservada.") }
        if registry.active[journal.candidateID] == nil {
            var source = stat(), quarantine = stat()
            let originalExists = lstat(journal.sourceURL.path, &source) == 0 && source.st_mode & S_IFMT == S_IFDIR
            let quarantineExists = journal.sourceQuarantine.map { lstat($0.path, &quarantine) == 0 } ?? false
            if originalExists && !quarantineExists && journal.operation != "restore" {
                try requireCanonical(journal.sourceURL)
                try finishRecovery(&journal)
                return CacheTransferItemResult(id: journal.candidateID, state: .none, detail: "Cache local preservado; cópias incompletas mantidas para revisão.", recordID: journal.id)
            }
        }
        if journal.operation == "restore", let expected = journal.publicationIdentity,
           let current = try? FileIdentity(journal.sourceURL), current.device == expected.device, current.inode == expected.inode {
            if let record {
                let parent = try GraphicalCacheFiles.openParent(of: journal.sourceURL, under: home, create: false)
                defer { close(parent) }
                let held = journal.heldLinkName ?? ".DiskWing-restored-link-" + journal.id.uuidString
                guard Paths.safeComponent(held) else { throw failure("O nome de recuperação deste cache é inválido e foi preservado.") }
                var metadata = stat()
                if fstatat(parent, held, &metadata, AT_SYMLINK_NOFOLLOW) == 0 { try removeHeldLink(name: held, parent: parent, expected: record) }
                registry.active.removeValue(forKey: journal.candidateID); try saveRegistry(registry)
            }
            try finishRecovery(&journal)
            return CacheTransferItemResult(id: journal.candidateID, state: .none, detail: "Restauração reconhecida; dados e cópias preservados.", recordID: journal.id)
        }
        if let record, managedLinkMatches(record), registry.active[journal.candidateID]?.id == record.id {
            // A durable registered route is safe to leave active. Recovery never
            // invents usage proof or removes a partially released original.
            if (journal.phase == .releasing || journal.interruptedAtPhase == .releasing), record.sourceQuarantine != nil {
                throw failure("A liberação ficou incompleta. A cópia no SSD e a recuperação foram preservadas para revisão.")
            }
            try finishRecovery(&journal, phase: .waitingForUsage)
            return CacheTransferItemResult(id: journal.candidateID, state: .configuredNeedsReopen, detail: "Destino preservado. Reabra o aplicativo e verifique o uso.", recordID: record.id, sourceReleased: record.sourceReleased, sourceLogicalBytes: record.sourceLogicalBytes)
        }
        let parent = try GraphicalCacheFiles.openParent(of: journal.sourceURL, under: home, create: false)
        defer { close(parent) }
        if let quarantine = journal.sourceQuarantine {
            guard quarantine.deletingLastPathComponent().path == journal.sourceURL.deletingLastPathComponent().path,
                  quarantine.lastPathComponent == ".DiskWing-cache-" + journal.id.uuidString,
                  try FileIdentity(quarantine) == journal.sourceIdentity,
                  try FileTree.digest(quarantine, cancellation: cancellation, workspace: store.base) == journal.sourceDigest else { throw failure("O original de recuperação mudou. Todas as cópias foram preservadas.") }
            var sourceInfo = stat()
            if fstatat(parent, journal.sourceURL.lastPathComponent, &sourceInfo, AT_SYMLINK_NOFOLLOW) == 0 {
                guard sourceInfo.st_mode & S_IFMT == S_IFLNK, let record, managedLinkMatches(record) else { throw failure("Já existe conteúdo no caminho original. Nenhuma cópia será sobrescrita.") }
                guard unlinkat(parent, journal.sourceURL.lastPathComponent, 0) == 0 else { throw failure("Não foi possível remover o direcionamento registrado.") }
            } else { guard errno == ENOENT else { throw failure("Não foi possível conferir o caminho original.") } }
            guard renameatx_np(parent, quarantine.lastPathComponent, parent, journal.sourceURL.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw failure("O caminho original reapareceu. As cópias foram preservadas.") }
            registry.active.removeValue(forKey: journal.candidateID); try saveRegistry(registry)
        } else {
            if let expected = journal.sourceIdentity {
                guard try FileIdentity(journal.sourceURL) == expected else { throw failure("O caminho original mudou. As cópias foram preservadas.") }
            } else {
                var metadata = stat()
                guard lstat(journal.sourceURL.path, &metadata) != 0, errno == ENOENT else { throw failure("O caminho original reapareceu. Ele foi preservado.") }
            }
        }
        try finishRecovery(&journal)
        progress(CacheTransferProgress(entryID: journal.candidateID, state: .none, detail: "Origem preservada; cópias de recuperação mantidas."))
        return CacheTransferItemResult(id: journal.candidateID, state: .none, detail: "Origem recuperada sem sobrescrever dados; cópias preservadas.", recordID: journal.id)
    }

    func finishRecovery(_ journal: inout GraphicalCacheJournal, phase: GraphicalCachePhase = .restored) throws {
        try saveJournal(&journal, phase: phase)
        let name = configurationName(journal.id)
        if FileManager.default.fileExists(atPath: store.base.appendingPathComponent(name).path) {
            var configuration = try readRecord(ConfigurationChange.self, name: name)
            guard configuration.schemaVersion == 1 else { throw failure("O registro deste cache usa uma versão desconhecida e foi preservado.") }
            configuration.state = "completed"; try store.writeDurably(configuration, name: name)
        }
    }
    func closePriorTransferAfterRestore(_ record: GraphicalCacheRegistration) throws {
        guard var previous = try? readRecord(GraphicalCacheJournal.self, name: journalName(record.id)),
              !previous.isUnsupported, previous.isPending else { return }
        previous.detail = "Cache atual restaurado de cópia verificada; recuperação anterior mantida."
        if let quarantine = record.sourceQuarantine { previous.preservedRecoveryURLs = (previous.preservedRecoveryURLs ?? []) + [quarantine] }
        try finishRecovery(&previous)
    }
    func candidateForRecord(_ record: GraphicalCacheRegistration) -> GraphicalCacheCandidate {
        GraphicalCacheCandidate(id: record.candidateID, applicationID: record.applicationID, applicationName: record.applicationName,
            applicationVersion: record.applicationVersion, applicationURL: record.applicationURL, sourceURL: record.sourceURL,
            scopeLabel: "Diretório de caches do Chrome; dados de perfil ficam no Mac.", logicalBytes: record.sourceLogicalBytes,
            allocatedBytes: record.sourceAllocatedBytes, canTransfer: true, isSimulated: record.isSimulated)
    }
    func removeHeldLink(name: String, parent: Int32, expected: GraphicalCacheRegistration) throws {
        var metadata = stat()
        guard fstatat(parent, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0, metadata.st_mode & S_IFMT == S_IFLNK,
              Int64(metadata.st_dev) == expected.linkDevice, UInt64(metadata.st_ino) == expected.linkInode else { throw failure("O direcionamento de recuperação mudou e foi preservado.") }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = readlinkat(parent, name, &buffer, buffer.count - 1)
        guard count >= 0, count < buffer.count - 1, String(cString: buffer) == expected.linkTarget else { throw failure("O direcionamento de recuperação não corresponde ao registro.") }
        guard unlinkat(parent, name, 0) == 0 else { throw failure("Não foi possível concluir a recuperação do direcionamento.") }
    }
    func requireClosed(_ candidate: GraphicalCacheCandidate) throws {
        guard !applicationRunning(candidate), try busyCheck([candidate.sourceURL], nil).isEmpty else { throw failure("Encerre o aplicativo antes de transferir ou restaurar seu cache.") }
    }
    func requireVolume(_ selected: VolumeInfo) throws -> URL {
        guard let actual = volumeProvider(selected.uuid), actual.uuid.caseInsensitiveCompare(selected.uuid) == .orderedSame,
              actual.path == selected.path, actual.isWritable, !actual.isInternal else { throw failure("Conecte o SSD selecionado e confirme que ele permite gravação.") }
        let root = URL(fileURLWithPath: actual.path); try requireCanonical(root); try FileTree.validateDestination(root)
        var filesystem = statfs()
        guard statfs(root.path, &filesystem) == 0 else { throw failure("Não foi possível identificar o formato do SSD.") }
        var name = filesystem.f_fstypename
        let format = withUnsafeBytes(of: &name) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
        guard format == "apfs" else { throw failure("A transferência de caches gráficos só foi qualificada em SSD APFS.") }
        return root
    }
    func requireUnchangedVolume(_ selected: VolumeInfo, identity: FileIdentity) throws {
        let root = try requireVolume(selected), current = try FileIdentity(root)
        guard current.device == identity.device, current.inode == identity.inode else { throw failure("O SSD foi substituído ou ficou indisponível. As cópias foram preservadas.") }
    }
    func requireCanonical(_ url: URL) throws {
        guard url.standardizedFileURL == url.resolvingSymlinksInPath() else { throw failure("O caminho foi redirecionado e será preservado.") }
        try requireScope([url])
    }
    func encoded<T: Encodable>(_ object: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(object), as: UTF8.self)
    }
    func requireSourceIdentity(_ identity: GraphicalCacheDirectoryIdentity?) throws -> GraphicalCacheDirectoryIdentity {
        guard let identity else { throw failure("A identidade da origem não pôde ser confirmada.") }; return identity
    }
    func resolvedVolumePath(_ uuid: String) throws -> String {
        guard let volume = volumeProvider(uuid), volume.isWritable, !volume.isInternal else { throw failure("Conecte o SSD selecionado e confirme que ele permite gravação.") }; return volume.path
    }
    func journalName(_ id: UUID) -> String { "graphical-operation-" + id.uuidString + ".json" }
    func configurationName(_ id: UUID) -> String { "configuration-graphical-" + id.uuidString + ".json" }
    func saveJournal(_ journal: inout GraphicalCacheJournal, phase: GraphicalCachePhase, invokeCheckpoint: Bool = true) throws {
        journal.phase = phase; journal.updatedAt = Date()
        try store.writeDurably(journal, name: journalName(journal.id))
        if invokeCheckpoint { try checkpoint(journal) }
    }
}

public struct GraphicalCacheUsageEvidence: Codable, Sendable {
    public let applicationVersion: String
    public let processIDs: [Int]
    public let observedReadAccess: Bool
    public let observedWriteAccess: Bool
    public let metadataFingerprint: String
    public let observedAt: Date
    public let isSimulated: Bool
    public init(applicationVersion: String, processIDs: [Int], observedReadAccess: Bool, observedWriteAccess: Bool,
                metadataFingerprint: String, observedAt: Date = Date(), isSimulated: Bool = false) {
        self.applicationVersion = applicationVersion; self.processIDs = processIDs
        self.observedReadAccess = observedReadAccess; self.observedWriteAccess = observedWriteAccess
        self.metadataFingerprint = metadataFingerprint; self.observedAt = observedAt; self.isSimulated = isSimulated
    }
}
public typealias GraphicalCacheUsageObserver = (GraphicalCacheCandidate, URL, String) throws -> GraphicalCacheUsageEvidence?

public struct GraphicalCacheDirectoryIdentity: Codable, Equatable, Sendable {
    public let device: Int64
    public let inode: UInt64
    public let birthNanoseconds: Int64
    public let owner: UInt32
    init(_ url: URL) throws {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_flags & UInt32(SF_DATALESS) == 0 else { throw CacheSSDError.message("A identidade da pasta de cache não pôde ser confirmada.") }
        device = Int64(metadata.st_dev); inode = UInt64(metadata.st_ino); owner = metadata.st_uid
        birthNanoseconds = Int64(metadata.st_birthtimespec.tv_sec) &* 1_000_000_000 &+ Int64(metadata.st_birthtimespec.tv_nsec)
    }
    func matches(_ current: Self, allowRemount: Bool = false) -> Bool {
        (allowRemount || device == current.device) && inode == current.inode && birthNanoseconds == current.birthNanoseconds && owner == current.owner
    }
}

public struct GraphicalCacheRegistration: Identifiable, Codable, Sendable {
    public let id: UUID
    public let candidateID: String
    public let applicationID: String
    public let applicationName: String
    public let applicationVersion: String
    public let applicationURL: URL?
    public let sourceURL: URL
    public let volumeUUID: String
    public let relativeDestination: String
    public var linkTarget: String
    public var linkDevice: Int64
    public var linkInode: UInt64
    public var sourceQuarantine: URL?
    public let sourceDigest: String?
    public let sourceLogicalBytes: Int64
    public let sourceAllocatedBytes: Int64
    public let releaseSourceAfterVerifiedUse: Bool
    public var sourceReleased: Bool
    public var state: CacheUsageState
    public var baselineFingerprint: String
    public var evidence: GraphicalCacheUsageEvidence?
    public let isSimulated: Bool
    public let createdAt: Date
    public var updatedAt: Date
    public var volumeIdentity: GraphicalCacheDirectoryIdentity? = nil
    public var destinationIdentity: GraphicalCacheDirectoryIdentity? = nil
    public var metadataVerification: GraphicalCacheVerificationProof? = nil
}

public struct GraphicalCacheJournal: Identifiable, Codable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let candidateID: String
    public let sourceURL: URL
    public let volumeUUID: String
    public let relativeDestination: String
    public var sourceIdentity: FileIdentity?
    public var sourceDigest: String?
    public var sourceQuarantine: URL?
    public var stagingURL: URL?
    public var phase: GraphicalCachePhase
    public var detail: String
    public var registration: GraphicalCacheRegistration?
    public let startedAt: Date
    public var updatedAt: Date
    public var operation: String? = nil
    public var interruptedAtPhase: GraphicalCachePhase? = nil
    public var preservedRecoveryURLs: [URL]? = nil
    public var publicationIdentity: FileIdentity? = nil
    public var heldLinkName: String? = nil
    public var metadataVerification: GraphicalCacheVerificationProof? = nil
    public var isPending: Bool { ![.waitingForUsage, .completed, .restored].contains(phase) }
    public var isUnsupported: Bool {
        schemaVersion != 1 || operation != nil && !["restore", "resume"].contains(operation ?? "") ||
        metadataVerification.map { $0.policyVersion != 1 } == true ||
        registration?.metadataVerification.map { $0.policyVersion != 1 } == true
    }
}

private struct GraphicalCacheRegistry: Codable {
    let schemaVersion: Int
    let installationID: String
    var active: [String: GraphicalCacheRegistration]
    init(installationID: String = UUID().uuidString) { schemaVersion = 1; self.installationID = installationID; active = [:] }
}

/// Each managed link is one qualified, application-owned cache directory. Profile
/// data is never moved. Original bytes remain quarantined until real cache activity.
public final class GraphicalCacheMigrationEngine {
    public let store: Store
    private let home: URL
    private let volumeProvider: (String) -> VolumeInfo?
    private let busyCheck: BusyCheck
    private let applicationRunning: (GraphicalCacheCandidate) -> Bool
    private let usageObserver: GraphicalCacheUsageObserver?
    private let freeBytes: (URL) -> Int64
    private let allowSimulatedCandidates: Bool
    private let permittedRoot: URL?
    private let permittedRootIdentity: GraphicalCacheDirectoryIdentity?
    private let checkpoint: (GraphicalCacheJournal) throws -> Void
    private let registryName = "graphical-caches.json"

    public init(store: Store = Store(), home: URL = FileManager.default.homeDirectoryForCurrentUser,
                volumeProvider: @escaping (String) -> VolumeInfo? = { Volumes.find(uuid: $0) },
                busyCheck: @escaping BusyCheck = { try BusyInspector.inspect(paths: $0, tool: $1) },
                applicationRunning: ((GraphicalCacheCandidate) -> Bool)? = nil,
                usageObserver: GraphicalCacheUsageObserver? = nil,
                allowSimulatedCandidates: Bool = false, permittedRoot: URL? = nil,
                checkpoint: @escaping (GraphicalCacheJournal) throws -> Void = { _ in },
                freeBytes: @escaping (URL) -> Int64 = { Volumes.free(at: $0) }) {
        self.store = store; self.home = Paths.physicalURL(home); self.volumeProvider = volumeProvider
        self.busyCheck = busyCheck; self.allowSimulatedCandidates = allowSimulatedCandidates
        self.permittedRoot = permittedRoot.map(Paths.physicalURL); self.checkpoint = checkpoint
        self.permittedRootIdentity = permittedRoot.flatMap { try? GraphicalCacheDirectoryIdentity(Paths.physicalURL($0)) }
        self.applicationRunning = applicationRunning ?? { candidate in
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == candidate.applicationID && !$0.isTerminated }
        }
        self.usageObserver = usageObserver; self.freeBytes = freeBytes
    }

    public func registrations() throws -> [GraphicalCacheRegistration] { try readRegistry().active.values.sorted { $0.createdAt < $1.createdAt } }
    public func pendingTransfers() throws -> [GraphicalCacheJournal] {
        let names = try recordNames(prefix: "graphical-operation-")
        return try names.map { name in
            let journal = try readRecord(GraphicalCacheJournal.self, name: name)
            guard !journal.isUnsupported else { throw failure("O registro deste cache usa uma versão desconhecida e foi preservado.") }
            return journal
        }.filter(\.isPending)
    }
    public func hasUnsafeRecoveryRecords() -> Bool {
        do {
            _ = try readRegistry()
            return try !pendingTransfers().isEmpty
        } catch { return true }
    }
    public func protectedPaths() -> [URL] {
        var result = [store.base]
        // Protection is deliberately broader than operational eligibility. A
        // future policy never authorizes an action, but its known paths remain
        // protected without resolving links or opening their contents.
        let known = try? readRecord(GraphicalCacheRegistry.self, name: registryName)
        for record in (known?.active.values.map { $0 } ?? []).prefix(4_096) {
            result.append(record.sourceURL); result.append(URL(fileURLWithPath: record.linkTarget))
            if let quarantine = record.sourceQuarantine { result.append(quarantine) }
            let parts = record.relativeDestination.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count <= 80, parts.allSatisfy({ Paths.safeComponent(String($0)) }),
               let volume = volumeProvider(record.volumeUUID), volume.uuid.caseInsensitiveCompare(record.volumeUUID) == .orderedSame {
                result.append(URL(fileURLWithPath: volume.path).appendingPathComponent(record.relativeDestination))
            }
        }
        let names = (try? recordNames(prefix: "graphical-operation-")) ?? []
        for name in names.prefix(4_096) {
            guard let journal = try? readRecord(GraphicalCacheJournal.self, name: name) else { continue }
            if journal.isPending || journal.isUnsupported { result.append(journal.sourceURL) }
            if let path = journal.sourceQuarantine { result.append(path) }
            if let path = journal.stagingURL { result.append(path) }
            result += journal.preservedRecoveryURLs ?? []
        }
        return result
    }
    public func plan(candidates: [GraphicalCacheCandidate], volume: VolumeInfo) -> CacheTransferPlan {
        CacheTransferPlan(destinationVolume: volume, entries: candidates.map { $0.transferEntry() })
    }
    public func status(candidate: GraphicalCacheCandidate) -> GraphicalCacheStatus {
        do {
            if try pendingTransfers().contains(where: { $0.candidateID == candidate.id }) {
                return GraphicalCacheStatus(candidateID: candidate.id, state: .error, detail: "A operação deste cache precisa de recuperação. Nenhuma nova liberação será feita.")
            }
            guard let record = try readRegistry().active[candidate.id] else {
                return GraphicalCacheStatus(candidateID: candidate.id, state: candidate.canTransfer ? .none : .exception,
                                            detail: candidate.canTransfer ? "Nenhum cache transferido." : candidate.blockedReason ?? "Este cache ainda não tem uma transferência qualificada.")
            }
            try validate(record)
            guard managedLinkMatches(record) else {
                return status(record, .error, "O caminho deste cache mudou. As cópias foram preservadas; revise a recuperação.")
            }
            guard versionMatches(candidate, record: record) else {
                return status(record, .exception, "A versão do aplicativo mudou. Revise o cache antes de confirmar novas operações.")
            }
            guard let currentDestination = try? destination(for: record) else {
                return status(record, .localTemporary, "SSD indisponível. O Chrome pode usar rede e memória temporária; o cache persistente do SSD não está disponível.")
            }
            guard currentDestination.path == record.linkTarget else {
                return status(record, .localTemporary, "O SSD mudou de caminho. Encerre o aplicativo e revise a retomada antes de voltar a usar seu cache persistente.")
            }
            return status(record, record.state, record.state == .ssdVerified ? "Uso do cache no SSD comprovado." : "Destino configurado. Reabra o aplicativo e verifique o uso antes de liberar a origem.")
        } catch {
            return GraphicalCacheStatus(candidateID: candidate.id, state: .error, detail: error.localizedDescription)
        }
    }

    public func transfer(candidate: GraphicalCacheCandidate, volume: VolumeInfo, releaseSource: Bool = true,
                         cancellation: CancellationFlag = CancellationFlag(),
                         progress: @escaping (CacheTransferProgress) -> Void = { _ in }) throws -> CacheTransferItemResult {
        try transferImpl(candidate: candidate, volume: volume, releaseSource: releaseSource, cancellation: cancellation, progress: progress)
    }
    public func verifyUsage(candidate: GraphicalCacheCandidate, cancellation: CancellationFlag = CancellationFlag(),
                            progress: @escaping (CacheTransferProgress) -> Void = { _ in }) throws -> GraphicalCacheStatus {
        try verifyUsageImpl(candidate: candidate, cancellation: cancellation, progress: progress)
    }
    public func restore(candidateID: String, cancellation: CancellationFlag = CancellationFlag(),
                        progress: @escaping (CacheTransferProgress) -> Void = { _ in }) throws -> CacheTransferItemResult {
        try restoreImpl(candidateID: candidateID, cancellation: cancellation, progress: progress)
    }
    public func resumeExternal(candidateID: String, cancellation: CancellationFlag = CancellationFlag(),
                               progress: @escaping (CacheTransferProgress) -> Void = { _ in }) throws -> CacheTransferItemResult {
        try resumeImpl(candidateID: candidateID, cancellation: cancellation, progress: progress)
    }
    public func recover(operationID: UUID, cancellation: CancellationFlag = CancellationFlag(),
                        progress: @escaping (CacheTransferProgress) -> Void = { _ in }) throws -> CacheTransferItemResult {
        try recoverImpl(operationID: operationID, cancellation: cancellation, progress: progress)
    }

    private func failure(_ text: String) -> Error { CacheSSDError.message(text) }
    private func status(_ record: GraphicalCacheRegistration, _ state: CacheUsageState, _ text: String) -> GraphicalCacheStatus {
        GraphicalCacheStatus(candidateID: record.candidateID, state: state, detail: text, recordID: record.id,
                             destinationURL: try? destination(for: record), sourceReleased: record.sourceReleased, verifiedAt: record.evidence?.observedAt)
    }
    private func requireScope(_ urls: [URL]) throws {
        if allowSimulatedCandidates && permittedRoot == nil { throw failure("O modo de amostras precisa de uma pasta isolada para estes caches.") }
        if let root = permittedRoot {
            let rootPath = GraphicalCacheFiles.normalizedSystemPath(root.path)
            func contains(_ path: String) -> Bool {
                let normalized = GraphicalCacheFiles.normalizedSystemPath(path)
                return normalized == rootPath || normalized.hasPrefix(rootPath + "/")
            }
            guard let identity = permittedRootIdentity, identity.matches(try GraphicalCacheDirectoryIdentity(root)),
                  urls.allSatisfy({ contains($0.path) && contains($0.resolvingSymlinksInPath().path) }) else { throw failure("O modo de amostras só permite os arquivos gerados para este teste.") }
        }
    }
    private func readRegistry() throws -> GraphicalCacheRegistry {
        let path = store.base.appendingPathComponent(registryName)
        var metadata = stat()
        if lstat(path.path, &metadata) != 0 {
            guard errno == ENOENT else { throw failure("Não foi possível ler os registros dos caches gráficos.") }
            let installation = (try? store.read(AppSettings.self, name: "settings.json"))?.installationID
            return GraphicalCacheRegistry(installationID: installation ?? UUID().uuidString)
        }
        let registry = try readRecord(GraphicalCacheRegistry.self, name: registryName)
        guard registry.schemaVersion == 1, Paths.safeComponent(registry.installationID),
              registry.installationID.utf8.count <= 200,
              !registry.installationID.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw failure("O registro deste cache usa uma versão desconhecida e foi preservado.") }
        for (key, registration) in registry.active {
            guard key == registration.candidateID else { throw failure("O registro deste cache está inconsistente e foi preservado.") }
            try validate(registration)
        }
        return registry
    }
    private func saveRegistry(_ registry: GraphicalCacheRegistry) throws {
        try requireScope([store.base])
        guard store.base.standardizedFileURL == store.base.resolvingSymlinksInPath() else { throw failure("O diretório de registros está indisponível.") }
        _ = try readRegistry()
        try store.writeDurably(registry, name: registryName)
    }
    private func readRecord<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        guard Paths.safeComponent(name), store.base.standardizedFileURL == store.base.resolvingSymlinksInPath() else { throw failure("O registro do cache foi redirecionado e será preservado.") }
        let descriptor = open(store.base.appendingPathComponent(name).path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw failure("O registro do cache está indisponível e será preservado.") }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true); var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_flags & UInt32(SF_DATALESS) == 0, metadata.st_size <= 8_388_608,
              let bytes = try file.read(upToCount: 8_388_609), bytes.count <= 8_388_608,
              bytes.count == metadata.st_size else { throw failure("O registro do cache está ilegível e será preservado.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: bytes)
    }
    private func recordNames(prefix: String) throws -> [String] {
        if !FileManager.default.fileExists(atPath: store.base.path) { return [] }
        guard store.base.standardizedFileURL == store.base.resolvingSymlinksInPath() else { throw failure("O diretório de registros está indisponível.") }
        return try FileManager.default.contentsOfDirectory(atPath: store.base.path).filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }
    }
    private func allJournals() throws -> [GraphicalCacheJournal] {
        try recordNames(prefix: "graphical-operation-").map { name in
            let journal = try readRecord(GraphicalCacheJournal.self, name: name)
            guard !journal.isUnsupported else { throw failure("O registro deste cache usa uma versão desconhecida e foi preservado.") }
            return journal
        }
    }
    private func validate(_ record: GraphicalCacheRegistration) throws {
        let components = record.relativeDestination.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard record.candidateID == GraphicalCacheCatalog.chromeCacheID, record.applicationID == GraphicalCacheCatalog.chromeBundleID,
              GraphicalCacheFiles.normalizedSystemPath(record.sourceURL.path) == GraphicalCacheFiles.normalizedSystemPath(home.appendingPathComponent(GraphicalCacheCatalog.chromeRelativePath).path),
              record.volumeIdentity != nil, record.destinationIdentity != nil,
              record.metadataVerification.map({ $0.policyVersion == 1 }) ?? true,
              components.count == 7, components[0] == "MacCaches", components[1] == "CacheSSD", components[3] == "graphical",
              components[4] == record.candidateID, components[5] == record.id.uuidString, components[6] == "data",
              (!record.isSimulated || allowSimulatedCandidates && permittedRoot != nil),
              record.state == .configuredNeedsReopen || record.state == .ssdVerified,
              record.state != .ssdVerified || record.evidence != nil,
              !record.sourceReleased || record.sourceQuarantine == nil,
              record.relativeDestination.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ Paths.safeComponent(String($0)) }) else { throw failure("O registro deste cache não corresponde a uma pasta qualificada.") }
        if let quarantine = record.sourceQuarantine {
            guard quarantine.deletingLastPathComponent().path == record.sourceURL.deletingLastPathComponent().path,
                  quarantine.lastPathComponent == ".DiskWing-cache-" + record.id.uuidString else { throw failure("O registro de recuperação deste cache é inválido e foi preservado.") }
        }
    }
    private func destination(for record: GraphicalCacheRegistration, allowRemount: Bool = false) throws -> URL {
        guard let volume = volumeProvider(record.volumeUUID), volume.uuid.caseInsensitiveCompare(record.volumeUUID) == .orderedSame,
              volume.isWritable, !volume.isInternal else { throw failure("Conecte o SSD selecionado e confirme que ele permite gravação.") }
        let destination = URL(fileURLWithPath: volume.path).appendingPathComponent(record.relativeDestination)
        guard let expectedRoot = record.volumeIdentity, let expectedData = record.destinationIdentity,
              expectedRoot.matches(try GraphicalCacheDirectoryIdentity(URL(fileURLWithPath: volume.path)), allowRemount: allowRemount),
              expectedData.matches(try GraphicalCacheDirectoryIdentity(destination), allowRemount: allowRemount) else { throw failure("A identidade do cache no SSD mudou. O original foi preservado.") }
        guard destination.standardizedFileURL == destination.resolvingSymlinksInPath(), FileManager.default.isWritableFile(atPath: destination.path) else { throw failure("O destino deste cache não está disponível ou foi redirecionado.") }
        try requireScope([destination]); return destination
    }
    private func managedLinkMatches(_ record: GraphicalCacheRegistration) -> Bool {
        var metadata = stat()
        return lstat(record.sourceURL.path, &metadata) == 0 && metadata.st_mode & S_IFMT == S_IFLNK &&
            Int64(metadata.st_dev) == record.linkDevice && UInt64(metadata.st_ino) == record.linkInode &&
            (try? FileManager.default.destinationOfSymbolicLink(atPath: record.sourceURL.path)) == record.linkTarget
    }
    private func versionMatches(_ candidate: GraphicalCacheCandidate, record: GraphicalCacheRegistration) -> Bool {
        if record.isSimulated { return allowSimulatedCandidates && candidate.isSimulated && permittedRoot != nil }
        guard candidate.applicationVersion == record.applicationVersion, let app = candidate.applicationURL,
              GraphicalCacheCatalog.platformIsQualified,
              GraphicalCacheCatalog.chromeSignatureIsQualified(app),
              !GraphicalCacheCatalog.chromeHasCustomStorage(),
              let info = GenericAppDetector.readBundleInfo(app), info["CFBundleIdentifier"] as? String == record.applicationID,
              info["CFBundleShortVersionString"] as? String == record.applicationVersion else { return false }
        return GraphicalCacheCatalog.qualifiedChromeVersions.contains(record.applicationVersion)
    }

}
